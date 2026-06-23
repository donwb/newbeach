import Foundation
import Observation
import BeachStatus

/// Main view model that drives all data for the Beach Ramp Status app.
@Observable
final class BeachViewModel {
    // MARK: - Published State

    var ramps: [Ramp] = []
    var tideInfo: TideInfo?
    var tideChart: TideChartData?
    var weather: WeatherInfo?
    var config: AppConfig?

    var isLoading = false
    var errorMessage: String?

    /// Current city filter — nil means "All".
    var selectedCity: String?

    /// Current status filter — nil means "All".
    var selectedStatus: StatusCategory?

    // MARK: - Computed

    /// Unique city names from loaded ramps, sorted alphabetically.
    var cities: [String] {
        Array(Set(ramps.map(\.cityDisplay))).sorted()
    }

    /// Ramps in the selected city, ignoring the status filter. This is the basis
    /// for the status counts so the summary reflects the chosen city, not every city.
    var cityRamps: [Ramp] {
        ramps.filter { selectedCity == nil || $0.cityDisplay == selectedCity }
    }

    /// Ramps filtered by current city and status selection.
    var filteredRamps: [Ramp] {
        cityRamps.filter { selectedStatus == nil || $0.category == selectedStatus }
    }

    /// Counts per status category, scoped to the selected city.
    var openCount: Int { cityRamps.filter { $0.category == .open }.count }
    var limitedCount: Int { cityRamps.filter { $0.category == .limited }.count }
    var closedCount: Int { cityRamps.filter { $0.category == .closed }.count }

    /// Water temperature display.
    var waterTempDisplay: String? {
        guard let avg = tideInfo?.waterTempAvg else { return nil }
        return "\(Int(avg))°F"
    }

    // MARK: - Beach Cam Video (iPad only)

    /// Fallback HLS URL used before the API config provides the real one.
    static let fallbackVideoStreamURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8")!

    /// Active beach-cam HLS URL — loaded from config, falls back to the sample.
    var videoStreamURL: URL = fallbackVideoStreamURL

    /// Bumped on each refresh attempt so the player rebuilds even when the
    /// re-resolved YouTube URL string comes back unchanged but the player is wedged.
    var videoStreamGeneration: Int = 0

    private static let videoRefreshMinInterval: TimeInterval = 30
    private var lastVideoRefreshAttempt: Date?
    private var videoRefreshTask: Task<Void, Never>?

    /// Called by the player on playback failure — asks the API to re-resolve the
    /// rotating YouTube HLS URL and swaps it in. Mirrors the tvOS behavior, with
    /// a client-side throttle and single-flight gate.
    @MainActor
    func refreshVideoStream() {
        if let last = lastVideoRefreshAttempt,
           Date().timeIntervalSince(last) < Self.videoRefreshMinInterval {
            return
        }
        if videoRefreshTask != nil { return }
        lastVideoRefreshAttempt = Date()
        videoStreamGeneration &+= 1

        videoRefreshTask = Task { @MainActor in
            defer { videoRefreshTask = nil }
            do {
                let newURL = try await api.refreshVideoStream()
                if newURL != videoStreamURL {
                    videoStreamURL = newURL
                }
            } catch {
                // Swallow — the server's periodic poll will catch up.
            }
        }
    }

    // MARK: - Networking

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Fetch all data from the API concurrently.
    @MainActor
    func loadAll() async {
        isLoading = true
        errorMessage = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRamps() }
            group.addTask { await self.loadTides() }
            group.addTask { await self.loadTideChart() }
            group.addTask { await self.loadWeather() }
            group.addTask { await self.loadConfig() }
        }

        // Default to New Smyrna Beach on first load
        if selectedCity == nil {
            let defaultCity = config.map { $0.defaultCity.titleCased } ?? "New Smyrna Beach"
            if cities.contains(defaultCity) {
                selectedCity = defaultCity
            }
        }

        isLoading = false
    }

    /// Refresh all data (for pull-to-refresh).
    @MainActor
    func refresh() async {
        await loadAll()
    }

    // MARK: - Individual Loaders

    @MainActor
    private func loadRamps() async {
        do {
            ramps = try await api.fetchRamps()
        } catch {
            errorMessage = "Failed to load ramps: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadTides() async {
        do {
            tideInfo = try await api.fetchTides()
        } catch {
            errorMessage = "Failed to load tides: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadTideChart() async {
        do {
            tideChart = try await api.fetchTideChart()
        } catch {
            errorMessage = "Failed to load tide chart: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadWeather() async {
        do {
            weather = try await api.fetchWeather()
        } catch {
            errorMessage = "Failed to load weather: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadConfig() async {
        do {
            config = try await api.fetchConfig()
            // Pick up the configured beach-cam stream URL (used by the iPad layout).
            if let urlString = config?.videoStreamURL,
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                videoStreamURL = url
            }
        } catch {
            // Non-critical — config just provides defaults
        }
    }
}
