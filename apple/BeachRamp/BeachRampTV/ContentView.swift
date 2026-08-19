//
//  ContentView.swift
//  BeachRampTV
//
//  Created by Don Browning on 3/11/26.
//

import SwiftUI
import BeachStatus

/// tvOS ambient board. Root composition only: sky gradient, board content,
/// night scrim. The board answers "can I get on the beach right now?" in the
/// verdict band before the grid is read; the background tracks the real sun
/// for New Smyrna Beach through sixteen phases.
struct ContentView: View {
    @State private var viewModel = TVViewModel()
    @FocusState private var focusedCamera: String?
    @State private var currentTime = ""
    @State private var sunAltitude: Double = 30
    @State private var sunRising = true
    /// The day's sun timeline, recomputed when the calendar day rolls over.
    /// Drives the sun ribbon.
    @State private var sunTimeline: SunTimeline?
    /// The current instant as a fraction (0…1) of the local day — the position
    /// of the "now" marker on the ribbon. Updated every tick.
    @State private var nowFraction: Double = 0
    @State private var solarDay: Date?
    @State private var timeTimer: Timer?
    /// Which stat detail overlay is open.
    @State private var detailPanel: DetailPanel = .none
    /// The Recent-changes overlay (Menu from the board).
    @State private var showActivity = false
    /// Which stat tile has focus. Owned here so closing a detail overlay can
    /// hand focus back to the tile that opened it.
    @FocusState private var focusedStat: DetailPanel?
    /// True while the Recent-changes overlay was opened from the rail button
    /// (vs. the Menu shortcut) — focus returns to the button on close.
    @State private var activityOpenedFromButton = false
    @FocusState private var recentChangesButtonFocused: Bool

    private let solar = SolarCalculator.newSmyrnaBeach

    /// Eastern time — the beach's local zone, used for the clock and sun times.
    private static let easternZone = TimeZone(identifier: "America/New_York")!

    /// Gregorian calendar pinned to Eastern time, for day-boundary math.
    private static var easternCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternZone
        return cal
    }

    private var palette: SkyPalette { SkyPalette.forSun(altitude: sunAltitude, isRising: sunRising) }

    #if DEBUG
    /// QA hooks (simulator screenshot verification, DEBUG only):
    /// --overlay-* opens an overlay directly; --sky-minutes N renders the
    /// board at that wall-clock minute (0–1439), mirroring the design mock's
    /// timeMinutes scrub; --simulate-stale backdates the last refresh.
    private static let launchArgs = ProcessInfo.processInfo.arguments
    private static let skyMinutesOverride: Int? = launchArgs
        .firstIndex(of: "--sky-minutes")
        .flatMap { idx in launchArgs.indices.contains(idx + 1) ? Int(launchArgs[idx + 1]) : nil }
    private static let simulateStale = launchArgs.contains("--simulate-stale")
    #endif

    init() {
        #if DEBUG
        let args = Self.launchArgs
        if args.contains("--overlay-outlook") { _detailPanel = State(initialValue: .outlook) }
        if args.contains("--overlay-weather") { _detailPanel = State(initialValue: .weather) }
        if args.contains("--overlay-activity") { _showActivity = State(initialValue: true) }
        #endif
    }

    var body: some View {
        ZStack {
            palette.gradient
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.ramps.isEmpty {
                ProgressView("Loading Beach Status…")
                    .font(.title2)
                    .foregroundStyle(.white)
            } else {
                boardContent
            }

            // Night dimming scrim — darkens the whole board after sunset.
            // Overlays render above it: they are opaque designed fields, not
            // part of the sky.
            Color.black
                .opacity(palette.dimOverlayOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            overlayLayer
        }
        .environment(\.skyPalette, palette)
        .animation(.easeInOut(duration: 2.0), value: sunAltitude)
        .onExitCommand {
            // Menu on the board opens Recent changes (an open overlay's own
            // handler wins while it has focus). Home still exits the app.
            if detailPanel == .none && !showActivity {
                showActivity = true
            }
        }
        .task {
            await viewModel.loadAll()
            viewModel.startAutoRefresh()
            startClock()
            #if DEBUG
            if Self.simulateStale {
                viewModel.stopAutoRefresh()
                viewModel.lastSuccessfulRefresh = Date().addingTimeInterval(-14 * 60)
            }
            #endif
        }
        .onChange(of: focusedCamera) { _, id in
            // Channel-flip feel: moving focus across the rail switches the
            // active stream live. selectCamera is a no-op when the id is
            // unchanged or the camera's URL isn't resolved yet.
            if let id { viewModel.selectCamera(id) }
        }
        .onChange(of: detailPanel) { old, new in
            // Hand focus back to the tile that opened the overlay. Deferred a
            // runloop so the tile is back in the focus hierarchy after the
            // overlay (which grabbed focus on appear) tears down.
            if new == .none && old != .none {
                DispatchQueue.main.async { focusedStat = old }
            }
        }
        .onChange(of: showActivity) { _, open in
            if !open && activityOpenedFromButton {
                activityOpenedFromButton = false
                DispatchQueue.main.async { recentChangesButtonFocused = true }
            }
        }
    }

    // MARK: - Overlays

    @ViewBuilder private var overlayLayer: some View {
        if showActivity {
            ActivityOverlay(
                city: viewModel.currentCity,
                entries: viewModel.todaysActivity,
                onClose: { showActivity = false }
            )
        } else {
            switch detailPanel {
            case .none:
                EmptyView()
            case .outlook:
                if let weekend = viewModel.weekend {
                    OutlookOverlay(
                        weekend: weekend,
                        surfLine: viewModel.surfLine,
                        onClose: { detailPanel = .none }
                    )
                }
            case .weather:
                WeatherOverlay(
                    tide: viewModel.tideInfo,
                    weather: viewModel.weather,
                    stationID: viewModel.config?.tideStation ?? "8721147",
                    onClose: { detailPanel = .none }
                )
            }
        }
    }

    // MARK: - Board Layout

    private var boardContent: some View {
        VStack(spacing: 0) {
            TopBar(
                city: viewModel.currentCity,
                time: currentTime,
                freshness: freshness,
                onNextCity: { viewModel.nextCity() }
            )

            VerdictBand(
                verdict: viewModel.verdict,
                stats: statTiles,
                focusedStat: $focusedStat,
                onSelect: { detailPanel = $0 }
            )
            .padding(.top, 22)

            RampGridView(
                ramps: viewModel.displayedRamps,
                staleAsOf: staleAsOf,
                outlookHints: outlookHints
            )
            .padding(.top, 26)

            SunRibbon(
                timeline: sunTimeline,
                nowFraction: nowFraction,
                isStale: viewModel.isStale
            )
            .padding(.top, 22)

            // The cam takes whatever height remains: growing any block above
            // shortens the cam rather than overflowing.
            TVVideoPlayerView(
                url: viewModel.videoStreamURL,
                rebuildToken: viewModel.videoStreamGeneration,
                isPlaying: $viewModel.isVideoPlaying,
                cameraName: viewModel.selectedCamera?.name ?? "Beach",
                isOffline: camOffline,
                otherLiveCount: otherLiveCameraCount,
                onPlaybackFailure: { viewModel.refreshVideoStream() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(.top, 20)

            if !viewModel.cameras.isEmpty {
                CoastlineRail(
                    cameras: viewModel.cameras,
                    selectedID: viewModel.selectedCameraID,
                    focusedCamera: $focusedCamera,
                    recentChangesFocused: $recentChangesButtonFocused,
                    onSelect: { viewModel.selectCamera($0) },
                    onRecentChanges: {
                        activityOpenedFromButton = true
                        showActivity = true
                    }
                )
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 60)
        .padding(.top, 56)
        .padding(.bottom, 52)
    }

    // MARK: - Derived Display Data

    private var freshness: Freshness {
        guard viewModel.isStale, let age = viewModel.dataAge else { return .live }
        return .stale(minutes: max(1, Int((age / 60).rounded())))
    }

    /// "as of" time for muted tiles when the board is stale.
    private var staleAsOf: String? {
        guard viewModel.isStale, let last = viewModel.lastSuccessfulRefresh else { return nil }
        return SinceFormatter.string(from: last)
    }

    /// Server prediction hints for the visible ramps, keyed by access id.
    private var outlookHints: [String: String] {
        viewModel.displayedRamps.reduce(into: [:]) { hints, ramp in
            if let hint = viewModel.outlookHint(for: ramp) {
                hints[ramp.accessID] = hint
            }
        }
    }

    private var camOffline: Bool {
        viewModel.selectedCamera.map { $0.url == nil } ?? false
    }

    private var otherLiveCameraCount: Int {
        viewModel.cameras.filter { $0.id != viewModel.selectedCameraID && $0.url != nil }.count
    }

    /// The two band tiles: outlook (predictions) leads, weather follows.
    /// The outlook tile drops out when the weekend feature is off; weather
    /// is always there.
    private var statTiles: [StatTileModel] {
        var tiles: [StatTileModel] = []
        if let outlookStat {
            tiles.append(outlookStat)
        }
        tiles.append(weatherStat)
        return tiles
    }

    /// The Outlook tile — the predictive lead: the next weekend day's
    /// verdict as the value ("Sat · Good", verdict-tinted), today's surf
    /// line as the detail (the overlay carries the untruncated version).
    /// Absent when the weekend outlook isn't available (old server, kill
    /// switch) — its overlay is the multi-day view, so surf alone isn't
    /// enough to earn the tile.
    private var outlookStat: StatTileModel? {
        guard let weekend = viewModel.weekend else { return nil }
        let days = weekend.weekendDays
        guard let first = days.first else { return nil }

        var detail = viewModel.surfLine ?? " "
        if viewModel.surfLine == nil, days.count > 1 {
            detail = "\(days[1].weekdayShort) · \(days[1].verdictLabel)"
        }
        return StatTileModel(
            label: "Outlook",
            value: "\(first.weekdayShort) · \(first.verdictLabel)",
            detail: detail,
            panel: .outlook,
            valueColor: first.verdictCategory.map { palette.statusColor(for: $0) }
        )
    }

    /// The Weather tile — the old tide / water·air / wind tiles folded into
    /// one: spot values up top, the tide's direction and next extreme below.
    private var weatherStat: StatTileModel {
        let water = viewModel.tideInfo?.waterTempAvg.map { "\(Int($0))°" } ?? "—"
        let air = viewModel.weather?.current.temperatureF.map { "\(Int($0))°" } ?? "—"
        var value = "\(water) · \(air)"
        if let current = viewModel.weather?.current {
            let direction = current.windDirection ?? ""
            let speed = current.windSpeed?.split(separator: " ").first.map(String.init) ?? ""
            let joined = "\(direction) \(speed)".trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { value += " · \(joined)" }
        }

        var detail = " "
        if let tide = viewModel.tideInfo {
            detail = tide.isRising ? "Tide rising" : "Tide dropping"
            if let next = VerdictBuilder.nextExtreme(in: tide, after: Date()) {
                detail += " · \(next.label.lowercased()) \(SinceFormatter.clock(next.time))"
            }
        }
        return StatTileModel(label: "Weather", value: value, detail: detail, panel: .weather)
    }

    // MARK: - Clock & Sun

    private func startClock() {
        tick()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            tick()
        }
    }

    /// Updates the clock and the sun's altitude (driving the background),
    /// advances the ribbon's "now" marker, and rebuilds the day's sun timeline
    /// when the calendar day rolls over.
    private func tick() {
        var now = Date()
        let calendar = Self.easternCalendar
        #if DEBUG
        if let minutes = Self.skyMinutesOverride {
            now = calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(minutes * 60))
        }
        #endif

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = Self.easternZone
        currentTime = formatter.string(from: now)

        withAnimation(.easeInOut(duration: 2.0)) {
            sunAltitude = solar.altitude(at: now)
            sunRising = solar.isRising(at: now)
        }

        nowFraction = SunTimeline.dayFraction(of: now, calendar: calendar)

        if solarDay == nil || !calendar.isDate(solarDay!, inSameDayAs: now) {
            solarDay = now
            sunTimeline = SunTimeline(day: now, solar: solar, calendar: calendar, zone: Self.easternZone)
        }
    }
}

#Preview {
    ContentView()
}
