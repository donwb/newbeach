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

    /// Called by the player on playback failure. Re-fetches the camera roster
    /// to pick up the freshest cron-pushed HLS URL for the active camera, and
    /// rebuilds the player. Preferred over the server-side re-resolve, which
    /// runs yt-dlp from the datacenter (YouTube IP-filters it); the home cron
    /// on a residential IP is the real freshness mechanism.
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
                let roster = try await api.fetchCameras()
                cameras = roster.cameras
                updateCameraHealth()
                if let url = selectedCamera?.url, url != videoStreamURL {
                    videoStreamURL = url
                }
            } catch {
                // Swallow — the home cron and next poll will catch up.
            }
        }
    }

    // MARK: - Data

    var ramps: [Ramp] = []
    var tideInfo: TideInfo?
    var tideChart: TideChartData?
    var weather: WeatherInfo?
    var config: AppConfig?
    /// Recent ramp status changes, newest first (unfiltered server feed).
    var activity: [ActivityEntry] = []
    /// Server-side open/close prediction. Non-critical: nil (old server or
    /// failed fetch) simply hides the tile hints.
    var outlook: Outlook?
    /// Six-day weekend outlook. Non-critical: nil (route disabled, old
    /// server, or failed fetch) hides the Weekend tile entirely.
    var weekend: WeekendOutlook?

    // MARK: - Freshness

    /// When the safety-critical ramps feed last loaded successfully. Tide,
    /// weather, and camera failures degrade their own tiles only; this stamp
    /// is what the freshness chip and stale treatment speak for.
    var lastSuccessfulRefresh: Date?

    /// Age of the ramp data, or nil before the first successful load.
    /// Recomputed whenever the board re-renders (the 30-second clock tick).
    var dataAge: TimeInterval? {
        lastSuccessfulRefresh.map { Date().timeIntervalSince($0) }
    }

    /// Stale after two missed 60-second refresh cycles.
    var isStale: Bool {
        (dataAge ?? 0) > VerdictBuilder.staleThreshold
    }

    // MARK: - Cameras
    /// Live camera roster (south-to-north), backing the cam caption strip.
    /// The strip renders roster order directly — fixed geographic order.
    var cameras: [Camera] = []
    /// When each currently-offline camera was first seen dark, keyed by id —
    /// the caption strip's "offline since 12:48 PM" sub-labels. Cleared the
    /// moment a camera's stream URL comes back.
    var cameraOfflineSince: [String: Date] = [:]
    /// The currently selected camera id. Nil until the roster loads, then set
    /// to the roster's default.
    var selectedCameraID: String?

    /// The selected camera, falling back to the first in the roster.
    var selectedCamera: Camera? {
        guard !cameras.isEmpty else { return nil }
        if let id = selectedCameraID, let cam = cameras.first(where: { $0.id == id }) {
            return cam
        }
        return cameras.first
    }

    /// Switch the active camera. Updating `videoStreamURL` makes the player view
    /// rebuild its AVPlayer (it observes `onChange(of: url)`).
    @MainActor
    func selectCamera(_ id: String) {
        guard id != selectedCameraID else { return }
        selectedCameraID = id
        applySelectedCameraURL()
    }

    /// Point `videoStreamURL` at the selected camera's stream, if resolved.
    @MainActor
    private func applySelectedCameraURL() {
        if let url = selectedCamera?.url, url != videoStreamURL {
            videoStreamURL = url
        }
    }

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
    // Explicit per-city display order (design spec: the tiles are numbered, so
    // ordering must read as deliberate). Cities not listed keep roster order.
    private static let rampOrder: [String: [String]] = [
        "New Smyrna Beach": ["beachway av", "crawford rd", "flagler av", "3rd av", "27th av"],
    ]

    var displayedRamps: [Ramp] {
        let cityRamps = ramps.filter { $0.cityDisplay == currentCity }
        guard let order = Self.rampOrder[currentCity] else { return cityRamps }
        return cityRamps.enumerated().sorted { a, b in
            let aIdx = order.firstIndex(of: a.element.rampName.lowercased()) ?? order.count + a.offset
            let bIdx = order.firstIndex(of: b.element.rampName.lowercased()) ?? order.count + b.offset
            return aIdx < bIdx
        }.map(\.element)
    }

    var allRamps: [Ramp] { ramps }

    var cities: [String] {
        Array(Set(ramps.map(\.cityDisplay))).sorted()
    }

    var openCount: Int { displayedRamps.filter { $0.category == .open }.count }
    var limitedCount: Int { displayedRamps.filter { $0.category == .limited }.count }
    var closedCount: Int { displayedRamps.filter { $0.category == .closed }.count }

    /// The board's one-line answer, regenerated on every render from held data.
    var verdict: Verdict {
        VerdictBuilder.build(
            ramps: displayedRamps,
            tide: tideInfo,
            sunset: SolarCalculator.newSmyrnaBeach.events(on: Date(), calendar: Self.easternCalendar).sunset,
            now: Date(),
            dataAge: dataAge
        )
    }

    /// Today's status changes for the current city, newest first — the
    /// Recent-changes overlay. The server feed is global; filter here exactly
    /// as the TRMNL handler does in Go.
    var todaysActivity: [ActivityEntry] {
        activity.filter { entry in
            entry.city?.titleCased == currentCity
                && Self.easternCalendar.isDate(entry.recordedAt, inSameDayAs: Date())
        }
    }

    private static let easternCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()

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
            group.addTask { await self.loadCameras() }
            group.addTask { await self.loadActivity() }
            group.addTask { await self.loadOutlook() }
            group.addTask { await self.loadWeekend() }
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
        do {
            ramps = try await api.fetchRamps()
            lastSuccessfulRefresh = Date()
        } catch {
            // Keep last-good data — the board renders it muted with the
            // freshness chip and "Last known:" verdict once stale.
            errorMessage = "Failed to load ramps"
        }
    }

    @MainActor
    private func loadActivity() async {
        do { activity = try await api.fetchActivity(limit: 100) }
        catch { /* non-critical — the overlay just shows what it has */ }
    }

    @MainActor
    private func loadOutlook() async {
        do { outlook = try await api.fetchOutlook() }
        catch { /* non-critical — tiles just drop their prediction hints */ }
    }

    @MainActor
    private func loadWeekend() async {
        do { weekend = try await api.fetchWeekendOutlook() }
        catch APIError.httpError(statusCode: 404) {
            // The WEEKEND_OUTLOOK_ENABLED kill switch unregisters the route —
            // this is "feature off", so drop the tile rather than keep stale days.
            weekend = nil
        }
        catch { /* transient failure — keep last-good data, tile stays */ }
    }

    /// The beach-wide casual surf line ("Clean chest-high — worth a paddle").
    /// Server-built, rendered verbatim; nil when the buoy is silent or the
    /// SURF_REPORT_ENABLED kill switch is off.
    var surfLine: String? {
        outlook?.surfReport?.line
    }

    /// The compact prediction hint for a tile: a coming closure for drivable
    /// ramps, the reopen estimate for tide-closed ones — the board always
    /// looks forward. Always the server's own string.
    func outlookHint(for ramp: Ramp) -> String? {
        outlook?.boardHint(forAccessID: ramp.accessID, category: ramp.category)
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
            // Legacy single-stream fallback: only used when the camera roster
            // hasn't selected anything yet (older server, or /cameras failed).
            // Once a camera is selected, the roster is the source of truth.
            if selectedCameraID == nil,
               let urlString = config?.videoStreamURL,
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                videoStreamURL = url
            }
        } catch { /* non-critical */ }
    }

    @MainActor
    private func loadCameras() async {
        do {
            let roster = try await api.fetchCameras()
            cameras = roster.cameras
            updateCameraHealth()
            if selectedCameraID == nil {
                selectedCameraID = roster.defaultID
            }
            applySelectedCameraURL()
        } catch { /* non-critical — keep current/fallback stream */ }
    }

    /// Stamp newly-dark cameras and clear recovered ones. First-seen time is
    /// the best "offline since" this client can honestly claim.
    private func updateCameraHealth() {
        for camera in cameras {
            if camera.url == nil {
                if cameraOfflineSince[camera.id] == nil {
                    cameraOfflineSince[camera.id] = Date()
                }
            } else {
                cameraOfflineSince[camera.id] = nil
            }
        }
    }

    // MARK: - Overnight

    /// The outlook entry proving the beach is in its overnight window —
    /// outside driving hours every ramp is `closed_now`/`overnight`, so any
    /// one of them speaks for the board. The county feed may still say OPEN
    /// overnight; the outlook is authoritative for this display.
    var overnightOutlook: RampOutlook? {
        outlook?.ramps.first { $0.risk == "closed_now" && $0.reason == "overnight" }
    }

    var isOvernight: Bool { overnightOutlook != nil }

    /// The v3 card state for a ramp: the outlook's overnight call wins, so
    /// an expected end-of-driving close never wears the red field.
    func rampState(for ramp: Ramp) -> TVRampState {
        if let entry = outlook?.ramp(for: ramp.accessID),
           entry.risk == "closed_now", entry.reason == "overnight" {
            return .overnight
        }
        switch ramp.category {
        case .open: return .open
        case .limited: return .limited
        case .closed: return .closed
        }
    }

    /// The ramp heading's right-hand summary: "5 ramps · all open",
    /// "3 open · 1 limited · 1 closed", "Closed overnight · 5 ramps".
    var rampSummary: String {
        let total = displayedRamps.count
        if isOvernight {
            return "Closed overnight · \(total) ramp\(total == 1 ? "" : "s")"
        }
        if closedCount == 0 && limitedCount == 0 {
            return "\(total) ramp\(total == 1 ? "" : "s") · all open"
        }
        var parts = ["\(openCount) open"]
        if limitedCount > 0 { parts.append("\(limitedCount) limited") }
        if closedCount > 0 { parts.append("\(closedCount) closed") }
        return parts.joined(separator: " · ")
    }
}
