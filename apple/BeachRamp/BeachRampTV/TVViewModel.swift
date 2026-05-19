import Foundation
import Observation
import BeachStatus

/// View model for the tvOS ambient dashboard — all data, auto-refreshing.
@Observable
final class TVViewModel {

    // MARK: - Video Configuration
    // Fallback URL used when the API hasn't provided one yet.
    static let fallbackVideoStreamURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8")!

    /// The active video stream URL — loaded from the API config, falls back to hardcoded.
    var videoStreamURL: URL = fallbackVideoStreamURL

    /// Ticks on every refresh attempt that clears the throttle, even when the
    /// URL string comes back unchanged. The player view observes this so it
    /// can rebuild AVPlayer for recovery — YouTube's manifest URL often stays
    /// the same across yt-dlp re-resolves, but the underlying player can still
    /// be stuck (expired segment tokens, prior failure) and needs a fresh
    /// AVPlayerItem.
    var videoStreamGeneration: Int = 0

    var isVideoPlaying = true

    func toggleVideo() {
        isVideoPlaying.toggle()
    }

    /// Min interval between client-driven refresh requests, regardless of how
    /// many AVPlayer failures fire. Server has its own cooldown but we avoid
    /// hammering it from the client too.
    private static let videoRefreshMinInterval: TimeInterval = 30
    private var lastVideoRefreshAttempt: Date?
    private var videoRefreshTask: Task<Void, Never>?

    /// Called by the player on playback failure. Asks the API to re-resolve
    /// the rotating YouTube HLS URL and swaps it in.
    @MainActor
    func refreshVideoStream() {
        if let last = lastVideoRefreshAttempt,
           Date().timeIntervalSince(last) < Self.videoRefreshMinInterval {
            return
        }
        if videoRefreshTask != nil { return }
        lastVideoRefreshAttempt = Date()

        // Bump the generation token before kicking off the network call. The
        // player view watches this and rebuilds AVPlayer even when the URL
        // comes back unchanged — the player was wedged for a reason and a
        // fresh AVPlayerItem is the only reliable recovery. Bumping outside
        // the task means a rebuild happens whether or not the API call
        // succeeds, so the stall watcher gets replaced and can fire again.
        // The 30s throttle above caps the rebuild rate.
        videoStreamGeneration &+= 1

        videoRefreshTask = Task { @MainActor in
            defer { videoRefreshTask = nil }
            do {
                let newURL = try await api.refreshVideoStream()
                if newURL != videoStreamURL {
                    videoStreamURL = newURL
                }
            } catch {
                // Swallow — periodic poll on the server will catch up.
            }
        }
    }

    // MARK: - Data

    var ramps: [Ramp] = []
    var tideInfo: TideInfo?
    var tideChart: TideChartData?
    var weather: WeatherInfo?
    var config: AppConfig?

    var isLoading = false
    var errorMessage: String?

    /// Currently selected city — nil means show the default.
    var selectedCity: String?

    /// Auto-refresh timer task handle.
    private var refreshTask: Task<Void, Never>?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    // MARK: - Computed

    var defaultCity: String {
        config.map { $0.defaultCity.titleCased } ?? "New Smyrna Beach"
    }

    var currentCity: String {
        selectedCity ?? defaultCity
    }

    // MARK: - Ramp Display Order
    // Preferred display order for NSB ramps. Ramps not listed sort to the end alphabetically.
    private static let nsbRampOrder = ["beachway av", "crawford rd", "3rd av", "flagler av", "27th av"]

    var displayedRamps: [Ramp] {
        ramps
            .filter { $0.cityDisplay == currentCity }
            .sorted { a, b in
                let aName = a.rampName.lowercased()
                let bName = b.rampName.lowercased()
                let aIdx = Self.nsbRampOrder.firstIndex(of: aName) ?? Int.max
                let bIdx = Self.nsbRampOrder.firstIndex(of: bName) ?? Int.max
                if aIdx != bIdx { return aIdx < bIdx }
                return aName < bName
            }
    }

    var allRamps: [Ramp] { ramps }

    var cities: [String] {
        Array(Set(ramps.map(\.cityDisplay))).sorted()
    }

    var openCount: Int { displayedRamps.filter { $0.category == .open }.count }
    var limitedCount: Int { displayedRamps.filter { $0.category == .limited }.count }
    var closedCount: Int { displayedRamps.filter { $0.category == .closed }.count }

    var currentTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter.string(from: Date())
    }

    // MARK: - Networking

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

        // Default city on first load
        if selectedCity == nil {
            let city = config.map { $0.defaultCity.titleCased } ?? "New Smyrna Beach"
            if cities.contains(city) {
                selectedCity = city
            }
        }

        isLoading = false
    }

    /// Start auto-refreshing every 60 seconds.
    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await loadAll()
            }
        }
    }

    /// Stop auto-refreshing.
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Cycle to the next city.
    @MainActor
    func nextCity() {
        guard !cities.isEmpty else { return }
        if let current = selectedCity, let idx = cities.firstIndex(of: current) {
            let next = cities.index(after: idx)
            selectedCity = next < cities.endIndex ? cities[next] : cities[0]
        } else {
            selectedCity = cities.first
        }
    }

    /// Cycle to the previous city.
    @MainActor
    func previousCity() {
        guard !cities.isEmpty else { return }
        if let current = selectedCity, let idx = cities.firstIndex(of: current) {
            if idx > cities.startIndex {
                selectedCity = cities[cities.index(before: idx)]
            } else {
                selectedCity = cities.last
            }
        } else {
            selectedCity = cities.last
        }
    }

    // MARK: - Individual Loaders

    @MainActor
    private func loadRamps() async {
        do { ramps = try await api.fetchRamps() }
        catch { errorMessage = "Failed to load ramps" }
    }

    @MainActor
    private func loadTides() async {
        do { tideInfo = try await api.fetchTides() }
        catch { errorMessage = "Failed to load tides" }
    }

    @MainActor
    private func loadTideChart() async {
        do { tideChart = try await api.fetchTideChart() }
        catch { /* non-critical */ }
    }

    @MainActor
    private func loadWeather() async {
        do { weather = try await api.fetchWeather() }
        catch { errorMessage = "Failed to load weather" }
    }

    @MainActor
    private func loadConfig() async {
        do {
            config = try await api.fetchConfig()
            // Update video stream URL from API if provided.
            if let urlString = config?.videoStreamURL,
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                videoStreamURL = url
            }
        } catch { /* non-critical */ }
    }
}
