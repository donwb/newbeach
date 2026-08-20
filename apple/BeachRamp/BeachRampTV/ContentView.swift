//
//  ContentView.swift
//  BeachRampTV
//
//  Created by Don Browning on 3/11/26.
//

import SwiftUI
import BeachStatus

/// UserDefaults key for the persisted display mode — the choice is made
/// once, not re-made every launch.
private let tvModeKey = "tvDisplayMode"

/// The tvOS board: two presentations of the same moment, one D-pad press
/// apart. Cam mode rests on the video at its native 680pt with only the
/// verdict, the surf sentence and the five ramp cards; press Down and the
/// board rises from the bottom — the cam settles to its v3 405pt band and
/// the heading, weekend panels and daylight band fill in. Press Up from the
/// caption strip and it drops away. The rule that makes the switch legible:
/// the verdict never moves — brand row, weather, clock and the big call sit
/// at the same coordinates in both modes; only the video's bottom edge
/// travels, and the ramp cards ride between modes rather than rebuild.
struct ContentView: View {
    @State private var viewModel = TVViewModel()
    /// The display mode, persisted across launches. Falls back to Cam mode
    /// after 10 idle minutes — the picture is the better thing to leave on
    /// a television.
    @AppStorage(tvModeKey) private var modeRaw = TVBoardMode.cam.rawValue
    /// Invisible focus target just below the cam band in Cam mode — a Down
    /// press from the caption strip lands here and opens the board.
    @FocusState private var expandCatcherFocused: Bool
    /// Measured top of the ramp-card grid within the board block, so the
    /// parked block in Cam mode puts the cards exactly at the ambient
    /// section's card position.
    @State private var cardsTopInBlock: CGFloat = 109
    /// Bumped when the verdict headline changes while Cam mode is up — the
    /// band flashes its accent bar once, in place. Never opens the board.
    @State private var verdictFlashToken = 0
    /// Last remote interaction we can observe (focus moves, selects,
    /// overlay traffic) — drives the 10-minute fallback to Cam mode.
    @State private var lastRemoteActivity = Date()
    @FocusState private var focusedCamera: String?
    @State private var currentTime = ""
    @State private var sunAltitude: Double = 30
    @State private var sunRising = true
    /// The day's sun timeline, recomputed when the calendar day rolls over.
    /// Drives the daylight band.
    @State private var sunTimeline: SunTimeline?
    /// The current instant as a fraction (0…1) of the local day — the position
    /// of the "now" marker on the band. Updated every tick.
    @State private var nowFraction: Double = 0
    @State private var solarDay: Date?
    @State private var timeTimer: Timer?
    /// The beach forecast overlay (opens from the weekend panels).
    @State private var showForecast = false
    /// The Recent-changes overlay (Menu from the board, or the heading button).
    @State private var showActivity = false
    /// Which weekend day panel has focus — owned here so closing the
    /// forecast overlay can hand focus back to the panel that opened it.
    @FocusState private var focusedDay: String?
    @State private var forecastOpenedFrom: String?
    /// True while Recent changes was opened from the heading button (vs. the
    /// Menu shortcut) — focus returns to the button on close.
    @State private var activityOpenedFromButton = false
    @FocusState private var recentChangesButtonFocused: Bool
    @FocusState private var cityFocused: Bool

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

    private var mode: TVBoardMode { TVBoardMode(rawValue: modeRaw) ?? .cam }

    /// The mode switch: 340ms, ease-out, one motion.
    private static let modeTransition: TimeInterval = 0.34
    /// Idle remote time before the board falls back to Cam mode.
    private static let idleFallback: TimeInterval = 10 * 60
    /// Card height + the ambient section's 40pt bottom inset — where the
    /// card row's top edge sits in Cam mode, measured from the screen bottom.
    private static let ambientCardsBottomInset: CGFloat = 40 + 218

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
        // --mode-cam / --mode-board force the persisted mode for screenshots;
        // overlays open from the board, so they imply Board mode.
        if args.contains("--mode-cam") {
            UserDefaults.standard.set(TVBoardMode.cam.rawValue, forKey: tvModeKey)
        }
        if args.contains("--mode-board") || args.contains("--overlay-outlook") || args.contains("--overlay-activity") {
            UserDefaults.standard.set(TVBoardMode.board.rawValue, forKey: tvModeKey)
        }
        if args.contains("--overlay-outlook") { _showForecast = State(initialValue: true) }
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

            overlayLayer
        }
        .environment(\.skyPalette, palette)
        .animation(.easeInOut(duration: 2.0), value: sunAltitude)
        .onExitCommand(perform: menuAction)
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
            noteActivity()
            // Channel-flip feel: moving focus across the caption strip
            // switches the active stream live. selectCamera is a no-op when
            // the id is unchanged or the camera's URL isn't resolved yet.
            if let id { viewModel.selectCamera(id) }
        }
        .onChange(of: expandCatcherFocused) { _, focused in
            // Down from the caption strip in Cam mode — the board rises.
            if focused { expandToBoard() }
        }
        .onChange(of: verdictDisplay) { old, new in
            // A ramp closing while Cam mode is up changes the verdict line
            // in place and flashes the accent bar once. It does not open the
            // board — a status change is not a reason to take the beach off
            // the screen.
            if mode == .cam, old.headline != new.headline {
                verdictFlashToken &+= 1
            }
        }
        .onChange(of: focusedDay) { _, _ in noteActivity() }
        .onChange(of: cityFocused) { _, _ in noteActivity() }
        .onChange(of: recentChangesButtonFocused) { _, _ in noteActivity() }
        .onChange(of: showForecast) { _, open in
            noteActivity()
            // Hand focus back to the day panel that opened the overlay,
            // deferred a runloop so the panel is back in the focus hierarchy
            // after the overlay (which grabbed focus on appear) tears down.
            if !open, let slot = forecastOpenedFrom {
                forecastOpenedFrom = nil
                DispatchQueue.main.async { focusedDay = slot }
            }
        }
        .onChange(of: showActivity) { _, open in
            noteActivity()
            if !open && activityOpenedFromButton {
                activityOpenedFromButton = false
                DispatchQueue.main.async { recentChangesButtonFocused = true }
            }
        }
    }

    // MARK: - Mode Switching

    /// Menu returns to Cam mode from the board (an open overlay's own
    /// handler wins while it has focus); from Cam mode it is unhandled, so
    /// the system exits to the Home screen. Recent changes stays reachable
    /// through the heading's button.
    private var menuAction: (() -> Void)? {
        guard mode == .board, !showForecast, !showActivity else { return nil }
        return { collapseToCam() }
    }

    private func noteActivity() {
        lastRemoteActivity = Date()
    }

    private func expandToBoard() {
        guard mode == .cam, !showForecast, !showActivity else { return }
        noteActivity()
        withAnimation(.easeOut(duration: Self.modeTransition)) {
            modeRaw = TVBoardMode.board.rawValue
        }
        // The catcher that got us here just went unfocusable; hand focus
        // back to the caption strip — row 0 of the board's focus rows.
        DispatchQueue.main.async { focusedCamera = viewModel.selectedCamera?.id }
    }

    private func collapseToCam() {
        guard mode == .board else { return }
        noteActivity()
        withAnimation(.easeOut(duration: Self.modeTransition)) {
            modeRaw = TVBoardMode.cam.rawValue
        }
        DispatchQueue.main.async { focusedCamera = viewModel.selectedCamera?.id }
    }

    // MARK: - Overlays

    @ViewBuilder private var overlayLayer: some View {
        if showActivity {
            ActivityOverlay(
                city: viewModel.currentCity,
                entries: viewModel.todaysActivity,
                onClose: { showActivity = false }
            )
        } else if showForecast, let weekend = viewModel.weekend {
            ForecastOverlay(
                city: viewModel.currentCity,
                weekend: weekend,
                onClose: { showForecast = false }
            )
        }
    }

    // MARK: - Board Layout

    /// The two-mode composition. The cam band tops a vertical stack whose
    /// remainder is the Cam-mode ambient section (surf sentence on its own
    /// dark ground); the board is one absolutely-positioned block that
    /// slides between its parked Cam-mode position (only its card row
    /// visible, landing at the ambient card slot) and y = 405. The cards
    /// therefore ride between modes rather than rebuild, while the board's
    /// heading, panels and daylight band crossfade in during the rise.
    private var boardContent: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    camBand
                    ambientArea
                }
                boardBlock(screenHeight: geo.size.height)
            }
        }
        .ignoresSafeArea()
    }

    private var camBand: some View {
        CamBand(
            streamURL: viewModel.videoStreamURL,
            rebuildToken: viewModel.videoStreamGeneration,
            isPlaying: $viewModel.isVideoPlaying,
            cameras: viewModel.cameras,
            selectedID: viewModel.selectedCameraID,
            offlineSince: viewModel.cameraOfflineSince,
            verdict: verdictDisplay,
            weatherCells: weatherCells,
            time: currentTime,
            staleMinutes: staleMinutes,
            mode: mode,
            flashToken: verdictFlashToken,
            focusedCamera: $focusedCamera,
            onSelectCamera: { viewModel.selectCamera($0); noteActivity() },
            onPlaybackFailure: { viewModel.refreshVideoStream() },
            onCollapse: { collapseToCam() }
        )
    }

    /// Cam mode's lower 400pt: the surf sentence on its own ground (white
    /// type needs to clear the pale end of the sky gradient). The ramp cards
    /// that appear to live here belong to the board block above. Constant
    /// day and night — the after-dark treatment is the feed's own darkness.
    private var ambientArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            AmbientSurfLine(model: surfPanel)
            Spacer(minLength: 0)
        }
        .padding(.top, 32)
        .padding(.horizontal, 64)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(boardHex: 0x041420).opacity(0.88),
                         Color(boardHex: 0x041420).opacity(0.74)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(alignment: .top) { expandCatcher }
        .opacity(mode == .cam ? 1 : 0)
    }

    /// Invisible focus target on the band's bottom edge, live only in Cam
    /// mode while the caption strip has focus (the `focusedCamera` gate
    /// keeps launch-time initial focus off it): nothing else is focusable
    /// down there, so a Down press always lands here and opens the board.
    private var expandCatcher: some View {
        Color(boardHex: 0x041420).opacity(0.02)
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .focusable(mode == .cam && focusedCamera != nil)
            .focused($expandCatcherFocused)
    }

    /// The board as one block — never reflowed mid-rise, only translated.
    private func boardBlock(screenHeight: CGFloat) -> some View {
        lowerArea
            .frame(height: screenHeight - CamBand.boardModeHeight)
            // Night dimming scrim — darkens the board after sunset, but
            // only below the band: the live feed is already dark at
            // night, and dimming it further reads as a dead cam. The
            // band has its own designed scrim. Cam mode's ambient ground
            // is already dark, so the dim rides the mode crossfade.
            .overlay(
                Color.black
                    .opacity(mode == .board ? palette.dimOverlayOpacity : 0)
                    .allowsHitTesting(false)
            )
            .offset(y: boardOffset(screenHeight: screenHeight))
    }

    private func boardOffset(screenHeight: CGFloat) -> CGFloat {
        if mode == .board { return CamBand.boardModeHeight }
        // Cam mode: park the block so its card row lands at the ambient
        // section's card slot; everything else in it is faded and disabled.
        return (screenHeight - Self.ambientCardsBottomInset) - cardsTopInBlock
    }

    /// Board chrome (heading, ahead band, daylight band) dissolves in Cam
    /// mode — the cards are the only part of the block both modes share.
    private var boardChromeOpacity: Double { mode == .board ? 1 : 0 }

    private var lowerArea: some View {
        VStack(spacing: 0) {
            RampHeading(
                city: viewModel.currentCity,
                summary: viewModel.rampSummary,
                cityFocused: $cityFocused,
                recentChangesFocused: $recentChangesButtonFocused,
                onNextCity: { viewModel.nextCity(); noteActivity() },
                onRecentChanges: {
                    activityOpenedFromButton = true
                    showActivity = true
                }
            )
            .opacity(boardChromeOpacity)
            .disabled(mode != .board)

            RampGridView(cards: rampCards, staleAsOf: staleAsOf)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named("tvBoardBlock")).minY
                } action: { cardsTopInBlock = $0 }
                .padding(.top, 18)

            AheadBand(
                surf: surfPanel,
                days: dayPanels,
                focusedDay: $focusedDay,
                onOpenForecast: {
                    forecastOpenedFrom = focusedDay
                    showForecast = true
                }
            )
            .padding(.top, 20)
            .opacity(boardChromeOpacity)
            .disabled(mode != .board)

            // A single spacer absorbs slack above the daylight band — no
            // band is ever centered into a shrinkable track.
            Spacer(minLength: 0)

            SunRibbon(
                timeline: sunTimeline,
                nowFraction: nowFraction,
                isStale: viewModel.isStale
            )
            .opacity(boardChromeOpacity)
        }
        .padding(.top, 24)
        .padding(.horizontal, 64)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "tvBoardBlock")
    }

    // MARK: - Derived Display Data

    private var staleMinutes: Int? {
        guard viewModel.isStale, let age = viewModel.dataAge else { return nil }
        return max(1, Int((age / 60).rounded()))
    }

    /// "as of" time for muted cards when the board is stale.
    private var staleAsOf: String? {
        guard viewModel.isStale, let last = viewModel.lastSuccessfulRefresh else { return nil }
        return SinceFormatter.string(from: last)
    }

    /// The verdict block: overnight is a factual neutral state with the
    /// server's own reopen copy; everything else comes from VerdictBuilder.
    private var verdictDisplay: TVVerdictDisplay {
        if !viewModel.isStale, let overnight = viewModel.overnightOutlook {
            return TVVerdictDisplay(
                headline: "Driving is done for today",
                subline: overnight.detail ?? overnight.headline,
                barColor: .white.opacity(0.55)
            )
        }
        let verdict = viewModel.verdict
        let bar: Color = switch verdict.category {
        case .open: BoardColor.verdictGood
        case .limited: BoardColor.verdictMixed
        case .closed: Color(boardHex: 0xC9301C)
        }
        return TVVerdictDisplay(headline: verdict.headline, subline: verdict.subline, barColor: bar)
    }

    private var rampCards: [TVRampCardModel] {
        viewModel.displayedRamps.map { ramp in
            TVRampCardModel(
                ramp: ramp,
                state: viewModel.rampState(for: ramp),
                shortLine: viewModel.outlookHint(for: ramp)
            )
        }
    }

    private var weatherCells: [WeatherCell] {
        var wind = "—"
        if let current = viewModel.weather?.current {
            let direction = current.windDirection ?? ""
            let speed = current.windSpeed?.split(separator: " ").first.map(String.init) ?? ""
            let joined = "\(direction) \(speed)".trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { wind = joined }
        }
        return [
            WeatherCell(label: "Water",
                        value: viewModel.tideInfo?.waterTempAvg.map { "\(Int($0))°" } ?? "—"),
            WeatherCell(label: "Air",
                        value: viewModel.weather?.current.temperatureF.map { "\(Int($0))°" } ?? "—"),
            WeatherCell(label: "Wind", value: wind),
        ]
    }

    /// The surf panel: the server's line and rip risk verbatim, the buoy
    /// facts underneath. No report = the honest "no read" state.
    private var surfPanel: SurfPanelModel {
        let context = viewModel.outlook?.surf
        if let report = viewModel.outlook?.surfReport {
            var ripLabel: String?
            var elevated = false
            if let rip = report.ripRisk {
                ripLabel = "Rip risk \(rip.lowercased())"
                elevated = rip.lowercased() != "low"
            }
            var parts: [String] = []
            if let height = report.heightLabel, !height.isEmpty {
                parts.append(height.prefix(1).uppercased() + height.dropFirst())
            }
            if let period = context?.dominantPeriodS {
                parts.append("\(Int(period.rounded()))s")
            }
            // Cam mode's sentence keeps height/period and folds a calm rip
            // read into the prose; the buoy-read time stays on the board
            // panel. An elevated rip is rendered separately, in amber.
            var sentenceParts = parts
            if let ripLabel, !elevated {
                sentenceParts.append(ripLabel.prefix(1).lowercased() + ripLabel.dropFirst())
            }
            if let at = report.observedAt ?? context?.observedAt {
                parts.append("buoy read \(agoText(at))")
            }
            return SurfPanelModel(
                line: report.line,
                ripLabel: ripLabel,
                ripElevated: elevated,
                detail: parts.isEmpty ? " " : parts.joined(separator: " · "),
                sentenceDetail: sentenceParts.isEmpty ? " " : sentenceParts.joined(separator: " · "),
                hasRead: true
            )
        }

        var detail = "Buoy is quiet — no recent report"
        if let at = context?.observedAt {
            detail = "Buoy last reported \(agoText(at))"
        }
        return SurfPanelModel(
            line: "No surf read right now",
            ripLabel: "No read",
            ripElevated: false,
            detail: detail,
            sentenceDetail: detail,
            hasRead: false
        )
    }

    /// The two weekend slots. Positions never move — on a Saturday the slot
    /// keeps its place and takes the label "Today · Saturday".
    private var dayPanels: [DayPanelModel] {
        guard let weekend = viewModel.weekend else { return [] }
        var days = Array(weekend.weekendDays.prefix(2))
        if days.isEmpty { days = Array(weekend.days.prefix(2)) }
        let today = Self.todayDateLabel()
        return days.enumerated().map { index, day in
            DayPanelModel(
                id: day.date,
                label: day.date == today ? "Today · \(day.weekday)" : day.weekday,
                verdict: day.verdict,
                headline: day.headline,
                metrics: metricsLine(for: day),
                cta: index == days.count - 1 ? "All 7 days ›" : nil
            )
        }
    }

    /// "93° · rain 20% · SW 8"
    private func metricsLine(for day: WeekendDay) -> String {
        var parts: [String] = []
        if let high = day.highTempF { parts.append("\(Int(high.rounded()))°") }
        if let rain = day.rainChancePct { parts.append("rain \(Int(rain.rounded()))%") }
        if let wind = day.windLabel {
            parts.append(wind.replacingOccurrences(of: " mph", with: ""))
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    /// Today's Eastern date in the server's "2026-08-22" label format.
    private static func todayDateLabel() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// "40 min ago" / "7 hours ago"
    private func agoText(_ date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return "\(hours) hour\(hours == 1 ? "" : "s") ago"
    }

    // MARK: - Clock & Sun

    private func startClock() {
        tick()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            tick()
        }
    }

    /// Updates the clock and the sun's altitude (driving the background),
    /// advances the band's "now" marker, and rebuilds the day's sun timeline
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
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Self.easternZone
        // Weekend clocks name the day — "Sat 10:18 AM" — because the board's
        // weekend copy is anchored to it.
        let weekday = calendar.component(.weekday, from: now)
        formatter.dateFormat = (weekday == 1 || weekday == 7) ? "EEE h:mm a" : "h:mm a"
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

        // 10 idle minutes on the board fall back to Cam mode, closing any
        // overlay on the way — the picture is the better thing to leave on
        // a television. Real wall clock on purpose: --sky-minutes scrubs
        // `now` for screenshots and must not fake idleness.
        if mode == .board, Date().timeIntervalSince(lastRemoteActivity) > Self.idleFallback {
            showForecast = false
            showActivity = false
            collapseToCam()
        }
    }
}

/// Cam mode's surf read — a baseline sentence, not a panel: kicker, the
/// server's line verbatim, and the height/period/rip facts. An elevated rip
/// risk enters the prose in amber; the no-read state mutes the line.
private struct AmbientSurfLine: View {
    let model: SurfPanelModel

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 24) {
            Text("Surf")
                .kickerStyle(opacity: 0.6)
            Text(model.line)
                .font(.system(size: 44, weight: .heavy))
                .tracking(44 * -0.02)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white.opacity(model.hasRead ? 1.0 : 0.72))
            Text(model.sentenceDetail)
                .font(.system(size: 24))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(model.hasRead ? 0.75 : 0.6))
            if model.ripElevated, let rip = model.ripLabel {
                Text(rip)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(BoardColor.amberAccent)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ContentView()
}
