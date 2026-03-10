import Foundation

/// Async networking client for the Beach Ramp Status API.
public actor APIClient {
    public static let shared = APIClient()

    /// Base URL for the production API.
    private let baseURL: URL

    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        baseURL: URL = URL(string: "https://beach-ramp-status-kff7g.ondigitalocean.app")!,
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

    // MARK: - Private

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

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
