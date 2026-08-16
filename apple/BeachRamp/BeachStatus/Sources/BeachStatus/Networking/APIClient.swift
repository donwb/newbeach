import Foundation

/// Async networking client for the Beach Ramp Status API.
public actor APIClient {
    public static let shared = APIClient()

    /// Base URL for the production API.
    private let baseURL: URL

    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        baseURL: URL = URL(string: "https://beach.donwb.com")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            // Try ISO 8601 with fractional seconds first
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: string) {
                return date
            }
            // Try standard ISO 8601
            if let date = ISO8601DateFormatter.standard.date(from: string) {
                return date
            }
            // Try just time format "HH:mm"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            timeFormatter.timeZone = TimeZone(identifier: "America/New_York")
            if let date = timeFormatter.date(from: string) {
                // Combine with today's date
                let cal = Calendar.current
                let now = Date()
                var comps = cal.dateComponents([.year, .month, .day], from: now)
                let timeComps = cal.dateComponents([.hour, .minute], from: date)
                comps.hour = timeComps.hour
                comps.minute = timeComps.minute
                if let combined = cal.date(from: comps) {
                    return combined
                }
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(string)"
            )
        }
        self.decoder = decoder
    }

    // MARK: - Endpoints

    /// Fetch all beach access ramps.
    public func fetchRamps() async throws -> [Ramp] {
        try await get("/api/v2/ramps")
    }

    /// Fetch tide information.
    public func fetchTides() async throws -> TideInfo {
        try await get("/api/v2/tides")
    }

    /// Fetch tide chart data (hourly points + high/low).
    public func fetchTideChart() async throws -> TideChartData {
        try await get("/api/v2/tides/chart")
    }

    /// Fetch current weather conditions and forecast.
    public func fetchWeather() async throws -> WeatherInfo {
        try await get("/api/v2/weather")
    }

    /// Fetch server configuration.
    public func fetchConfig() async throws -> AppConfig {
        try await get("/api/v2/config")
    }

    /// Fetch the live camera roster (ordered south-to-north) plus the default
    /// camera id. Backs the tvOS camera switcher. Re-fetching this is also the
    /// preferred playback-failure recovery for non-default cameras: it returns
    /// the freshest HLS URLs the home cron has pushed, without relying on the
    /// datacenter-bound server-side re-resolve.
    public func fetchCameras() async throws -> CameraRoster {
        try await get("/api/v2/cameras")
    }

    /// Fetch recent ramp status changes, newest first. The server caps
    /// `limit` at 200. `city`, `since`, and `ramp` (access id) filters are
    /// applied server-side when given.
    public func fetchActivity(limit: Int = 50, city: String? = nil,
                              since: Date? = nil, ramp: String? = nil) async throws -> [ActivityEntry] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let city {
            query.append(URLQueryItem(name: "city", value: city))
        }
        if let since {
            query.append(URLQueryItem(name: "since", value: ISO8601DateFormatter.standard.string(from: since)))
        }
        if let ramp {
            query.append(URLQueryItem(name: "ramp", value: ramp))
        }
        return try await get("/api/v2/activity", query: query)
    }

    /// Fetch one ramp's contiguous status intervals over the trailing window
    /// (default 48h server-side, clamped 1...168). Backs the detail screen's
    /// today band. Keyed by the numeric database id (`Ramp.id`), not the
    /// county access id.
    public func fetchIntervals(rampID: Int, hours: Int = 48) async throws -> RampIntervals {
        try await get("/api/v2/ramps/\(rampID)/intervals",
                      query: [URLQueryItem(name: "hours", value: String(hours))])
    }

    /// Fetch service health. `ingester.lastPollAt` is the real GIS feed
    /// timestamp — the input to the stale-board state.
    public func fetchHealth() async throws -> HealthStatus {
        try await get("/api/v2/health")
    }

    /// Fetch the server-side open/close prediction (schedule + per-ramp tide
    /// outlook). All prose is server-built; render it verbatim.
    public func fetchOutlook() async throws -> Outlook {
        try await get("/api/v2/outlook")
    }

    /// Ask the server to re-resolve the YouTube live HLS URL. Called by the
    /// tvOS player when playback fails (the cached URL has rotated). The
    /// server coalesces concurrent calls and applies a cooldown.
    public func refreshVideoStream() async throws -> URL {
        struct Response: Decodable {
            let videoStreamURL: String
            enum CodingKeys: String, CodingKey { case videoStreamURL = "video_stream_url" }
        }
        let response: Response = try await post("/api/v2/video/refresh")
        guard let url = URL(string: response.videoStreamURL) else {
            throw APIError.invalidResponse
        }
        return url
    }

    // MARK: - Private

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]? = nil) async throws -> T {
        try await send(path: path, method: "GET", query: query)
    }

    private func post<T: Decodable>(_ path: String) async throws -> T {
        try await send(path: path, method: "POST")
    }

    private func send<T: Decodable>(path: String, method: String, query: [URLQueryItem]? = nil) async throws -> T {
        var url = baseURL.appendingPathComponent(path)
        if let query, !query.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - Errors

public enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "Server error (\(code))"
        case .decodingError(let error):
            return "Data error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Date Formatters

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
