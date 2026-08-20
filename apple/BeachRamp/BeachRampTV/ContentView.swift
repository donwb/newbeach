//
//  ContentView.swift
//  BeachRampTV
//
//  Created by Don Browning on 3/11/26.
//

import SwiftUI
import BeachStatus

/// tvOS board, design v3: panorama header, inline selectors. The cam holds
/// the top 405pt at its true aspect and carries the verdict; cam switching
/// is a caption strip on the video's own bottom edge; ramp-city switching
/// is the heading above the ramp cards. The recovered space below goes to
/// surf and the weekend, with the daylight band closing the screen.
struct ContentView: View {
    @State private var viewModel = TVViewModel()
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
        .onExitCommand {
            // Menu on the board opens Recent changes (an open overlay's own
            // handler wins while it has focus). Home still exits the app.
            if !showForecast && !showActivity {
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
            // Channel-flip feel: moving focus across the caption strip
            // switches the active stream live. selectCamera is a no-op when
            // the id is unchanged or the camera's URL isn't resolved yet.
            if let id { viewModel.selectCamera(id) }
        }
        .onChange(of: showForecast) { _, open in
            // Hand focus back to the day panel that opened the overlay,
            // deferred a runloop so the panel is back in the focus hierarchy
            // after the overlay (which grabbed focus on appear) tears down.
            if !open, let slot = forecastOpenedFrom {
                forecastOpenedFrom = nil
                DispatchQueue.main.async { focusedDay = slot }
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
        } else if showForecast, let weekend = viewModel.weekend {
            ForecastOverlay(
                city: viewModel.currentCity,
                weekend: weekend,
                onClose: { showForecast = false }
            )
        }
    }

    // MARK: - Board Layout

    private var boardContent: some View {
        VStack(spacing: 0) {
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
                focusedCamera: $focusedCamera,
                onSelectCamera: { viewModel.selectCamera($0) },
                onPlaybackFailure: { viewModel.refreshVideoStream() }
            )

            lowerArea
                // Night dimming scrim — darkens the board after sunset, but
                // only below the band: the live feed is already dark at
                // night, and dimming it further reads as a dead cam. The
                // band has its own designed scrim.
                .overlay(
                    Color.black
                        .opacity(palette.dimOverlayOpacity)
                        .allowsHitTesting(false)
                )
        }
        .ignoresSafeArea()
    }

    private var lowerArea: some View {
        VStack(spacing: 0) {
            RampHeading(
                city: viewModel.currentCity,
                summary: viewModel.rampSummary,
                cityFocused: $cityFocused,
                recentChangesFocused: $recentChangesButtonFocused,
                onNextCity: { viewModel.nextCity() },
                onRecentChanges: {
                    activityOpenedFromButton = true
                    showActivity = true
                }
            )

            RampGridView(cards: rampCards, staleAsOf: staleAsOf)
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

            // A single spacer absorbs slack above the daylight band — no
            // band is ever centered into a shrinkable track.
            Spacer(minLength: 0)

            SunRibbon(
                timeline: sunTimeline,
                nowFraction: nowFraction,
                isStale: viewModel.isStale
            )
        }
        .padding(.top, 24)
        .padding(.horizontal, 64)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let at = report.observedAt ?? context?.observedAt {
                parts.append("buoy read \(agoText(at))")
            }
            return SurfPanelModel(
                line: report.line,
                ripLabel: ripLabel,
                ripElevated: elevated,
                detail: parts.isEmpty ? " " : parts.joined(separator: " · "),
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
    }
}

#Preview {
    ContentView()
}
