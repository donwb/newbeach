//
//  ContentView.swift
//  BeachRampTV
//
//  Created by Don Browning on 3/11/26.
//

import SwiftUI
import BeachStatus

/// The video-first board (2026-08-20 handoff). The panorama is the app: a
/// fixed 1920×340 band that is never cropped further, never covered, never
/// moved. Under it, the information ledger; over neither, ever, anything.
/// Two rules carry the design: a pull surface (Beach outlook, Ramp detail)
/// replaces the ledger and never the picture, and red means closed and
/// nothing else — focus, selection and the all-open verdict are dry sand.
/// The ground behind it all is the shared sixteen-phase SkyPalette at full
/// brightness — the evolving sky Don asked back — with TVSky's ink veils
/// over the header and ledger keeping type legible on the pale day phases;
/// there is no mode toggle any more.
struct ContentView: View {
    @State private var viewModel = TVViewModel()
    @FocusState private var focus: RootFocus?
    /// The open pull surface. Replaces the cam strip + ledger only.
    @State private var activeSurface: TVSurface?
    /// Where focus was when a surface opened — restored on close.
    @State private var focusBeforeSurface: RootFocus?
    /// First visible row of the windowed ramp list.
    @State private var rampTopIndex = 0
    /// Bumped when the verdict headline changes in place — the bar flashes
    /// once. A status change never opens a surface or steals focus.
    @State private var verdictFlashToken = 0
    /// Last remote interaction we can observe — drives the 10-minute idle
    /// reset (surfaces close, focus clears, the ledger stays).
    @State private var lastRemoteActivity = Date()
    @State private var currentTime = ""
    @State private var sunAltitude: Double = 30
    @State private var sunRising = true
    @State private var timeTimer: Timer?

    private let solar = SolarCalculator.newSmyrnaBeach

    private static let easternZone = TimeZone(identifier: "America/New_York")!
    private static var easternCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternZone
        return cal
    }

    private var sky: SkyPalette { SkyPalette.forSun(altitude: sunAltitude, isRising: sunRising) }

    /// Idle remote time before surfaces close and focus clears.
    private static let idleReset: TimeInterval = 10 * 60

    #if DEBUG
    /// QA hooks (screenshot verification, DEBUG only): --surface-outlook /
    /// --surface-ramp-detail[=ACCESS_ID] open a pull surface once data has
    /// loaded; --sky-minutes N renders at that wall-clock minute;
    /// --simulate-stale backdates the last refresh.
    private static let launchArgs = ProcessInfo.processInfo.arguments
    private static let skyMinutesOverride: Int? = launchArgs
        .firstIndex(of: "--sky-minutes")
        .flatMap { idx in launchArgs.indices.contains(idx + 1) ? Int(launchArgs[idx + 1]) : nil }
    private static let simulateStale = launchArgs.contains("--simulate-stale")
    private static let surfaceOutlookArg = launchArgs.contains("--surface-outlook")
    private static let surfaceRampArg: String?? = launchArgs
        .first { $0.hasPrefix("--surface-ramp-detail") }
        .map { arg in
            let parts = arg.split(separator: "=", maxSplits: 1)
            return parts.count == 2 ? String(parts[1]) : nil
        }
    /// --stream-url <url>: force the picture band's stream (player-path QA).
    private static let streamOverride: URL? = launchArgs
        .firstIndex(of: "--stream-url")
        .flatMap { idx in launchArgs.indices.contains(idx + 1) ? URL(string: launchArgs[idx + 1]) : nil }
    #endif

    var body: some View {
        ZStack {
            sky.gradient
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.ramps.isEmpty {
                ProgressView("Loading Beach Status…")
                    .font(.archivo(28, weight: .semiBold))
                    .foregroundStyle(TVInk.type)
            } else {
                boardContent
            }
        }
        .environment(\.skyPalette, sky)
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
            applyLaunchSurface()
            if let url = Self.streamOverride { viewModel.videoStreamURL = url }
            #endif
        }
        .onChange(of: focus) { _, target in
            noteActivity()
            // Channel-flip feel: moving focus across the cam strip switches
            // the active stream live. selectCamera no-ops on same id or an
            // unresolved URL.
            if case .cam(let id) = target { viewModel.selectCamera(id) }
        }
        .onChange(of: viewModel.selectedCameraID) { _, id in
            // Initial focus: the cam strip, once the roster names a cam.
            if focus == nil, let id { focus = .cam(id) }
        }
        .onChange(of: verdictModel.headline) { old, new in
            if old != new { verdictFlashToken &+= 1 }
        }
    }

    // MARK: - Composition

    private var boardContent: some View {
        VStack(spacing: 0) {
            HeaderBand(
                weatherCells: weatherCells,
                time: currentTime,
                staleMinutes: staleMinutes,
                surfaceOpen: activeSurface != nil,
                focus: $focus,
                onOpenOutlook: { openSurface(.outlook) }
            )
            .background(TVSky.headerVeil)

            PictureBand(
                streamURL: viewModel.videoStreamURL,
                rebuildToken: viewModel.videoStreamGeneration,
                isPlaying: $viewModel.isVideoPlaying,
                selectedOffline: selectedCamOffline,
                onPlaybackFailure: { viewModel.refreshVideoStream() }
            )

            bottomArea
                .background(TVSky.ledgerVeil)
        }
        .ignoresSafeArea()
    }

    /// The swappable 630pt: cam strip + ledger at rest, a pull surface when
    /// one is open. The header and the picture above do not move a pixel.
    @ViewBuilder private var bottomArea: some View {
        switch activeSurface {
        case .outlook:
            SurfaceScaffold(identifier: "surface.outlook", focus: $focus, onClose: closeSurface) {
                BeachOutlookSurface(city: viewModel.currentCity, rows: outlookRows)
            }
        case .rampDetail(let ramp):
            SurfaceScaffold(identifier: "surface.rampDetail", focus: $focus, onClose: closeSurface) {
                RampDetailSurface(
                    ramp: liveRamp(for: ramp),
                    kicker: detailKicker(for: ramp),
                    surfSentence: viewModel.outlook?.surfReport?.line,
                    prediction: viewModel.outlook?.ramp(for: ramp.accessID)?.headline,
                    intervals: viewModel.rampIntervals?.ramp.accessID == ramp.accessID
                        ? viewModel.rampIntervals : nil,
                    tideDirection: viewModel.tideInfo?.tideDirection,
                    tideChart: viewModel.tideChart,
                    now: Date()
                )
            }
        case nil:
            VStack(spacing: 0) {
                CamStrip(
                    cameras: viewModel.cameras,
                    selectedID: viewModel.selectedCameraID,
                    offlineSince: viewModel.cameraOfflineSince,
                    focus: $focus
                )
                LedgerView(
                    verdict: verdictModel,
                    flashToken: verdictFlashToken,
                    city: viewModel.currentCity,
                    rows: rampRows,
                    topIndex: $rampTopIndex,
                    surf: surfBox,
                    weekend: weekendSlots,
                    focus: $focus,
                    upTargetCamID: viewModel.selectedCamera?.id,
                    onCycleCity: cycleCity,
                    onSelect: { row in
                        if let ramp = viewModel.sortedLedgerRamps.first(where: { $0.accessID == row.id }) {
                            openSurface(.rampDetail(ramp))
                        }
                    },
                    onActivity: noteActivity
                )
            }
            .transition(.opacity)
        }
    }

    // MARK: - Surfaces

    private func openSurface(_ surface: TVSurface) {
        noteActivity()
        focusBeforeSurface = focus
        withAnimation(.easeOut(duration: TVMetrics.surfaceTransition)) {
            activeSurface = surface
        }
        DispatchQueue.main.async { focus = .surface }
        if case .rampDetail(let ramp) = surface {
            Task { await viewModel.loadIntervals(for: ramp) }
        }
    }

    private func closeSurface() {
        guard activeSurface != nil else { return }
        noteActivity()
        withAnimation(.easeOut(duration: TVMetrics.surfaceTransition)) {
            activeSurface = nil
        }
        // Restore focus where it was, one runloop later so the ledger is
        // back in the hierarchy. A row that left the window (sorting moved
        // it) clamps to the ramps header.
        let stashed = focusBeforeSurface
        focusBeforeSurface = nil
        DispatchQueue.main.async {
            if case .ramp(let id) = stashed,
               !visibleRowIDs.contains(id) {
                focus = .rampsHeader
                return
            }
            focus = stashed ?? viewModel.selectedCamera.map { .cam($0.id) }
        }
    }

    /// Menu with a surface open closes it; at rest it is unhandled, so the
    /// system exits to the Home screen.
    private var menuAction: (() -> Void)? {
        activeSurface == nil ? nil : { closeSurface() }
    }

    private var visibleRowIDs: [String] {
        let rows = rampRows
        let top = max(0, min(rampTopIndex, max(0, rows.count - RampsBox.visibleRows)))
        return rows[top..<min(rows.count, top + RampsBox.visibleRows)].map(\.id)
    }

    private func cycleCity(_ direction: Int) {
        if direction > 0 { viewModel.nextCity() } else { viewModel.previousCity() }
        rampTopIndex = 0
    }

    private func noteActivity() {
        lastRemoteActivity = Date()
    }

    // MARK: - Display models

    private var selectedCamOffline: Bool {
        viewModel.selectedCamera.map { $0.url == nil } ?? false
    }

    private var staleMinutes: Int? {
        guard viewModel.isStale, let age = viewModel.dataAge else { return nil }
        return max(1, Int((age / 60).rounded()))
    }

    /// The verdict: server-built city copy rendered verbatim when the server
    /// provides it and the data is live; VerdictBuilder otherwise (older
    /// server, stale board — the builder carries the stale voice). The bar
    /// color stays a client fact: red only when a ramp is actually closed.
    private var verdictModel: TVVerdictModel {
        if !viewModel.isStale, let cv = viewModel.currentCityVerdict {
            return TVVerdictModel(
                headline: cv.headline,
                detail: cv.detail,
                barColor: barColor(for: cv.state)
            )
        }
        if !viewModel.isStale, let overnight = viewModel.overnightOutlook {
            return TVVerdictModel(
                headline: "Driving is done for today",
                detail: overnight.detail ?? overnight.headline,
                barColor: TVInk.barMuted
            )
        }
        let verdict = viewModel.verdict
        let bar: Color = viewModel.closedCount > 0 ? TVInk.closed : TVInk.sand
        return TVVerdictModel(headline: verdict.headline, detail: verdict.subline, barColor: bar)
    }

    private func barColor(for state: String) -> Color {
        switch state {
        case "all_open", "golden": TVInk.sand
        case "some_closed": viewModel.closedCount > 0 ? TVInk.closed : TVInk.sand
        case "overnight": TVInk.barMuted
        default: TVInk.barMuted
        }
    }

    /// The ledger rows: closures on top, Now factual, Next the server's own
    /// prediction strings verbatim ("Clear all day" is the one fixed label,
    /// mapped from the typed `risk == none` field the way pills map colors).
    private var rampRows: [TVRampRowModel] {
        viewModel.sortedLedgerRamps.map { ramp in
            let entry = viewModel.outlook?.ramp(for: ramp.accessID)
            let next: String?
            switch entry?.risk {
            case "none": next = "Clear all day"
            case "closed_now": next = entry?.reopen?.label
            default: next = entry?.short ?? entry?.reopen?.label
            }
            // Overnight the outlook is authoritative: the county feed may
            // still read OPEN after the turtle-season close, and a row that
            // says Open next to "opens around 8am" contradicts itself.
            let overnight = entry?.risk == "closed_now" && entry?.reason == "overnight"
            return TVRampRowModel(
                id: ramp.accessID,
                name: ramp.rampDisplayName,
                nowLabel: overnight ? "Closed" : tvStatusWord(ramp.accessStatus),
                isClosed: overnight || ramp.category == .closed,
                nextLabel: next
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

    /// The surf block: the server's line and rip risk verbatim, buoy facts
    /// under it. v1 has only the "Now" window — paging arrives with server
    /// support for future windows.
    private var surfBox: TVSurfBoxModel {
        let context = viewModel.outlook?.surf
        if let report = viewModel.outlook?.surfReport {
            var parts: [String] = []
            if let height = report.heightLabel, !height.isEmpty {
                parts.append(height.prefix(1).uppercased() + height.dropFirst())
            }
            if let period = context?.dominantPeriodS {
                parts.append("\(Int(period.rounded()))s")
            }
            if let rip = report.ripRisk {
                parts.append("rip risk \(rip.lowercased())")
            }
            if let at = report.observedAt ?? context?.observedAt {
                parts.append("buoy read \(agoText(at))")
            }
            return TVSurfBoxModel(
                windowLabel: "Now",
                headline: report.line,
                detail: parts.isEmpty ? " " : parts.joined(separator: " · "),
                hasRead: true
            )
        }
        var detail = "Buoy is quiet — no recent report"
        if let at = context?.observedAt {
            detail = "Buoy last reported \(agoText(at))"
        }
        return TVSurfBoxModel(windowLabel: "Now", headline: "No surf read right now",
                              detail: detail, hasRead: false)
    }

    /// The two weekend slots: server copy, compacted for the card (the
    /// best-window label is the server's own string).
    private var weekendSlots: [TVWeekendSlot] {
        guard let weekend = viewModel.weekend else { return [] }
        var days = Array(weekend.weekendDays.prefix(2))
        if days.isEmpty { days = Array(weekend.days.prefix(2)) }
        let today = Self.todayDateLabel()
        return days.map { day in
            TVWeekendSlot(
                id: day.date,
                dayName: day.date == today ? "Today · \(day.weekday)" : day.weekday,
                headline: day.bestWindow.map { "Best \($0.label)" } ?? day.headline,
                metrics: slotMetrics(for: day)
            )
        }
    }

    private func slotMetrics(for day: WeekendDay) -> String {
        var parts: [String] = []
        if let high = day.highTempF { parts.append("\(Int(high.rounded()))°") }
        if let risk = day.closureRiskLabel, !risk.isEmpty {
            parts.append(risk.prefix(1).lowercased() + risk.dropFirst())
        } else if let wind = day.windLabel, !wind.isEmpty {
            parts.append(wind)
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    /// The outlook table rows. "Any time" / "No real window" are fixed
    /// labels mapped from typed fields (window absence + the risk label),
    /// same contract as pill colors.
    private var outlookRows: [TVOutlookDayRow] {
        guard let weekend = viewModel.weekend else { return [] }
        let today = Self.todayDateLabel()
        return weekend.days.map { day in
            let worst = day.closureRiskLabel == "All-day close risk"
            let window: String
            if let label = day.bestWindow?.label {
                window = label
            } else {
                window = worst ? "No real window" : "Any time"
            }
            return TVOutlookDayRow(
                id: day.date,
                day: day.date == today ? "Today" : day.weekday,
                high: day.highTempF.map { "\(Int($0.rounded()))°" } ?? "—",
                rain: day.rainChancePct.map { "\(Int($0.rounded()))%" } ?? "—",
                surf: day.surfLabel ?? "—",
                bestWindow: window,
                closureRisk: day.closureRiskLabel ?? "—",
                isToday: day.date == today,
                isWorstRisk: worst
            )
        }
    }

    /// The detail surface re-reads the live ramp each render so a status
    /// change updates the open surface in place.
    private func liveRamp(for ramp: Ramp) -> Ramp {
        viewModel.ramps.first { $0.accessID == ramp.accessID } ?? ramp
    }

    private func detailKicker(for ramp: Ramp) -> String {
        let index = viewModel.displayedRamps.firstIndex { $0.accessID == ramp.accessID }
        let number = index.map { String(format: "%02d", $0 + 1) } ?? "—"
        return "Ramp \(number) · \(ramp.cityDisplay)"
    }

    private static func todayDateLabel() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func agoText(_ date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return "\(hours) hour\(hours == 1 ? "" : "s") ago"
    }

    // MARK: - Clock & sun

    private func startClock() {
        tick()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            tick()
        }
    }

    /// Updates the clock, moves the sun (the ground follows it), and runs
    /// the idle reset. Real wall clock for idleness on purpose —
    /// --sky-minutes scrubs `now` for screenshots and must not fake it.
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
        let weekday = calendar.component(.weekday, from: now)
        formatter.dateFormat = (weekday == 1 || weekday == 7) ? "EEE h:mm a" : "h:mm a"
        currentTime = formatter.string(from: now)

        withAnimation(.easeInOut(duration: 2.0)) {
            sunAltitude = solar.altitude(at: now)
            sunRising = solar.isRising(at: now)
        }

        // Idle: surfaces close and focus clears; the ledger stays — there is
        // no mode to fall back to any more.
        if Date().timeIntervalSince(lastRemoteActivity) > Self.idleReset {
            if activeSurface != nil { closeSurface() }
            if focus != nil { focus = nil }
        }
    }

    #if DEBUG
    /// Launch-arg surfaces, applied once data is loaded (the ramp object has
    /// to exist). Tolerates a failed fetch — no data, no surface.
    private func applyLaunchSurface() {
        if Self.surfaceOutlookArg {
            openSurface(.outlook)
            return
        }
        if let idArg = Self.surfaceRampArg {
            let ramp: Ramp?
            if let id = idArg {
                ramp = viewModel.ramps.first { $0.accessID == id }
            } else {
                ramp = viewModel.displayedRamps.first
            }
            if let ramp { openSurface(.rampDetail(ramp)) }
        }
    }
    #endif
}

#Preview {
    ContentView()
}
