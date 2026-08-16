import Foundation
import Observation
import WidgetKit
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
    var health: HealthStatus?
    /// Server-side open/close prediction. Non-critical: nil (old server or
    /// failed fetch) hides the board hints and detail outlook line.
    var outlook: Outlook?

    var isLoading = false

    /// Current city filter — defaults to the config default after first load.
    var selectedCity: String?

    /// Current status filter — nil means "All".
    var selectedStatus: StatusCategory?

    /// iPad: show only favorited ramps.
    var favoritesOnly = false

    /// Recent city-wide status changes for the iPad board's Recent Changes
    /// section.
    var recentActivity: [ActivityEntry] = []

    /// Favorited ramp access ids, shared with the widgets via the App Group.
    var favorites: Set<String> = BeachViewModel.loadFavorites()

    /// Whether the landscape live-cam view is presented (iPhone).
    var camPresented = false

    /// When ramps last loaded successfully. Feeds the stale state alongside
    /// the server's own feed timestamp.
    private(set) var lastSuccessfulRefresh: Date?

    /// QA hook (`--simulate-stale`): backdates the data so the stale board
    /// state can be reviewed without unplugging the ingester.
    private static let simulateStale = ProcessInfo.processInfo.arguments.contains("--simulate-stale")

    // MARK: - Computed

    /// Unique city names from loaded ramps, sorted alphabetically.
    var cities: [String] {
        Array(Set(ramps.map(\.cityDisplay))).sorted()
    }

    /// Ramps in the selected city in board order, ignoring the status filter.
    /// Basis for the filter counts so they reflect the chosen city.
    var cityRamps: [Ramp] {
        ramps.filter { selectedCity == nil || $0.cityDisplay == selectedCity }.boardOrdered()
    }

    /// Ramps filtered by current city, status, and favorites selection, in
    /// board order.
    var filteredRamps: [Ramp] {
        cityRamps.filter {
            (selectedStatus == nil || $0.category == selectedStatus)
                && (!favoritesOnly || favorites.contains($0.accessID))
        }
    }

    /// Counts per status category, scoped to the selected city.
    var openCount: Int { cityRamps.filter { $0.category == .open }.count }
    var limitedCount: Int { cityRamps.filter { $0.category == .limited }.count }
    var closedCount: Int { cityRamps.filter { $0.category == .closed }.count }

    /// Age of the board data: the older of "since we last fetched" and the
    /// server's own GIS-poll timestamp, so a dead ingester behind a healthy
    /// API still reads stale.
    func dataAge(now: Date = Date()) -> TimeInterval? {
        if Self.simulateStale { return 45 * 60 }
        var ages: [TimeInterval] = []
        if let lastSuccessfulRefresh {
            ages.append(now.timeIntervalSince(lastSuccessfulRefresh))
        }
        if let poll = health?.ingester?.lastPollAt {
            ages.append(now.timeIntervalSince(poll))
        }
        return ages.max()
    }

    /// Whether the board should render the stale state.
    var isStale: Bool {
        (dataAge() ?? 0) > VerdictBuilder.staleThreshold
    }

    /// The board's one-line answer, built from the selected city's ramps.
    func verdict(now: Date = Date()) -> Verdict {
        let sunset = SolarCalculator.newSmyrnaBeach.events(on: now).sunset
        return VerdictBuilder.build(
            ramps: cityRamps,
            tide: tideInfo,
            sunset: sunset,
            now: now,
            dataAge: dataAge(now: now)
        )
    }

    // MARK: - Ramp Detail

    /// Per-ramp 48h intervals, keyed by access id. Refreshed on detail open.
    private(set) var intervalsByRamp: [String: RampIntervals] = [:]
    /// Per-ramp 48h activity feed, keyed by access id.
    private(set) var activityByRamp: [String: [ActivityEntry]] = [:]

    /// Load the detail screen's data for one ramp. Cached values render
    /// immediately; both fetches refresh behind them.
    @MainActor
    func loadDetail(for ramp: Ramp) async {
        async let intervals = try? api.fetchIntervals(rampID: ramp.id, hours: 48)
        async let activity = try? api.fetchActivity(
            limit: 50,
            since: Date().addingTimeInterval(-48 * 3600),
            ramp: ramp.accessID
        )
        if let intervals = await intervals {
            intervalsByRamp[ramp.accessID] = intervals
        }
        if let activity = await activity {
            activityByRamp[ramp.accessID] = activity
        }
    }

    /// The projection line for a ramp against its closure threshold, nil
    /// without a threshold or a crossing.
    func projection(for ramp: Ramp) -> ClosureProjection? {
        guard let chart = tideChart else { return nil }
        return ClosureProjector.project(
            ramp: ramp,
            hourly: chart.hourly,
            highLow: chart.highLow
        )
    }

    // MARK: - Server Outlook

    /// The compact board hint ("closure likely ~1:30pm"), or nil when there's
    /// nothing worth saying. Mirrors the web/tvOS boards: only for drivable
    /// ramps the server flags, always the server's own string.
    func outlookHint(for ramp: Ramp) -> String? {
        guard ramp.category != .closed,
              let entry = outlook?.ramp(for: ramp.accessID),
              entry.flagsRisk else { return nil }
        return entry.short
    }

    /// The detail screen's forward-looking line. The server outlook wins —
    /// timing headline for predicted risk, detail copy otherwise (it carries
    /// the reopen story for closed ramps) — with the client-side
    /// ClosureProjector as the fallback for old servers, same as the web.
    func outlookLine(for ramp: Ramp) -> String? {
        guard let entry = outlook?.ramp(for: ramp.accessID) else {
            return projection(for: ramp)?.line
        }
        if entry.flagsRisk {
            return entry.headline
        }
        return entry.detail ?? entry.headline
    }

    // MARK: - Favorites

    func isFavorite(_ ramp: Ramp) -> Bool {
        favorites.contains(ramp.accessID)
    }

    @MainActor
    func toggleFavorite(_ ramp: Ramp) {
        if !favorites.insert(ramp.accessID).inserted {
            favorites.remove(ramp.accessID)
        }
        Self.favoritesDefaults?.set(Array(favorites), forKey: Self.favoritesKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static let favoritesKey = "favoriteRampIDs"

    /// App Group defaults once the entitlement exists; standard until then so
    /// favorites survive either way.
    private static var favoritesDefaults: UserDefaults? {
        SnapshotStore.sharedDefaults ?? .standard
    }

    private static func loadFavorites() -> Set<String> {
        Set(favoritesDefaults?.stringArray(forKey: favoritesKey) ?? [])
    }

    // MARK: - Beach Cam Video

    /// Fallback HLS URL used before the API config provides the real one.
    static let fallbackVideoStreamURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8")!

    /// Active beach-cam HLS URL — loaded from config, falls back to the sample.
    var videoStreamURL: URL = fallbackVideoStreamURL

    /// Bumped on each refresh attempt so the player rebuilds even when the
    /// re-resolved YouTube URL string comes back unchanged but the player is wedged.
    var videoStreamGeneration: Int = 0

    /// Live camera roster (south-to-north).
    var cameras: [Camera] = []
    /// Selected camera id; nil until the roster loads, then the roster default.
    var selectedCameraID: String?

    /// The selected camera, falling back to the first in the roster.
    var selectedCamera: Camera? {
        guard !cameras.isEmpty else { return nil }
        if let id = selectedCameraID, let cam = cameras.first(where: { $0.id == id }) {
            return cam
        }
        return cameras.first
    }

    /// Switch the active camera. Updating `videoStreamURL` makes the player
    /// rebuild (it observes `onChange(of: url)`).
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

    private static let videoRefreshMinInterval: TimeInterval = 30
    private var lastVideoRefreshAttempt: Date?
    private var videoRefreshTask: Task<Void, Never>?

    /// Called by the player on playback failure. Re-fetches the camera roster to
    /// pick up the freshest cron-pushed HLS URL for the active camera. Preferred
    /// over the server-side re-resolve (yt-dlp from the datacenter is IP-filtered;
    /// the home cron on a residential IP is the real freshness mechanism). Mirrors
    /// the tvOS behavior, with a client-side throttle and single-flight gate.
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
                let roster = try await api.fetchCameras()
                cameras = roster.cameras
                if let url = selectedCamera?.url, url != videoStreamURL {
                    videoStreamURL = url
                }
            } catch {
                // Swallow — the home cron and next poll will catch up.
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

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRamps() }
            group.addTask { await self.loadTides() }
            group.addTask { await self.loadTideChart() }
            group.addTask { await self.loadWeather() }
            group.addTask { await self.loadConfig() }
            group.addTask { await self.loadCameras() }
            group.addTask { await self.loadHealth() }
            group.addTask { await self.loadOutlook() }
        }

        // Default to New Smyrna Beach on first load
        if selectedCity == nil {
            let defaultCity = config.map { $0.defaultCity.titleCased } ?? "New Smyrna Beach"
            if cities.contains(defaultCity) {
                selectedCity = defaultCity
            }
        }

        // After the city default settles — the feed is city-scoped.
        await loadRecentActivity()

        publishSnapshot()

        isLoading = false
    }

    /// Refresh all data (for pull-to-refresh).
    @MainActor
    func refresh() async {
        await loadAll()
    }

    /// Persist the board for the widgets and wake their timelines. No-op
    /// until the last load produced ramps.
    @MainActor
    private func publishSnapshot() {
        guard !ramps.isEmpty, let fetchedAt = lastSuccessfulRefresh else { return }
        SnapshotStore.save(BoardSnapshot(
            ramps: ramps,
            tide: tideInfo,
            tideChart: tideChart,
            weather: weather,
            outlook: outlook,
            fetchedAt: fetchedAt
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Individual Loaders
    //
    // Loader failures are deliberately silent: the board's stale state (built
    // from dataAge) is the user-facing error surface, not inline messages.

    @MainActor
    private func loadRamps() async {
        do {
            ramps = try await api.fetchRamps()
            lastSuccessfulRefresh = Date()
        } catch {
            // Stale state takes over via dataAge().
        }
    }

    @MainActor
    private func loadTides() async {
        tideInfo = (try? await api.fetchTides()) ?? tideInfo
    }

    @MainActor
    private func loadTideChart() async {
        tideChart = (try? await api.fetchTideChart()) ?? tideChart
    }

    @MainActor
    private func loadWeather() async {
        weather = (try? await api.fetchWeather()) ?? weather
    }

    @MainActor
    private func loadHealth() async {
        health = (try? await api.fetchHealth()) ?? health
    }

    @MainActor
    private func loadOutlook() async {
        outlook = (try? await api.fetchOutlook()) ?? outlook
    }

    @MainActor
    private func loadRecentActivity() async {
        // The DB stores cities uppercase; the display name is title-cased.
        let city = selectedCity?.uppercased()
        recentActivity = (try? await api.fetchActivity(limit: 12, city: city)) ?? recentActivity
    }

    @MainActor
    private func loadConfig() async {
        do {
            config = try await api.fetchConfig()
            // Legacy single-stream fallback — only until the camera roster selects
            // something (older server, or /cameras failed). Once a camera is
            // selected, the roster is the source of truth for the cam.
            if selectedCameraID == nil,
               let urlString = config?.videoStreamURL,
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                videoStreamURL = url
            }
        } catch {
            // Non-critical — config just provides defaults
        }
    }

    @MainActor
    private func loadCameras() async {
        do {
            let roster = try await api.fetchCameras()
            cameras = roster.cameras
            if selectedCameraID == nil {
                selectedCameraID = roster.defaultID
            }
            applySelectedCameraURL()
        } catch {
            // Non-critical — keep the current/fallback stream.
        }
    }
}
