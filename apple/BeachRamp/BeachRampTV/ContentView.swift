//
//  ContentView.swift
//  BeachRampTV
//
//  Created by Don Browning on 3/11/26.
//

import SwiftUI
import Charts
import BeachStatus

/// tvOS ambient dashboard — full-screen status board with ramps, tide, weather.
/// The background tracks the real sun for New Smyrna Beach, shifting through
/// dawn, day, golden hour, and a dimmed night as the day progresses.
struct ContentView: View {
    @State private var viewModel = TVViewModel()
    @FocusState private var focusedCamera: String?
    @FocusState private var cityFocused: Bool
    @State private var currentTime = ""
    @State private var sunAltitude: Double = 30
    @State private var sunRising = true
    /// The day's sun timeline (dawn → golden → noon → sunset → dusk), recomputed
    /// when the calendar day rolls over. Drives the bottom day-timeline bar.
    @State private var sunTimeline: SunTimeline?
    /// The current instant as a fraction (0…1) of the local day — the position of
    /// the "now" marker on the bar. Updated every tick.
    @State private var nowFraction: Double = 0
    @State private var solarDay: Date?
    @State private var timeTimer: Timer?

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

    var body: some View {
        ZStack {
            palette.gradient
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.ramps.isEmpty {
                ProgressView("Loading Beach Status…")
                    .font(.title2)
                    .foregroundStyle(.white)
            } else {
                dashboardContent
            }

            // Night dimming scrim — darkens the whole board after sunset.
            Color.black
                .opacity(palette.dimOverlayOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 2.0), value: sunAltitude)
        .task {
            await viewModel.loadAll()
            viewModel.startAutoRefresh()
            startClock()
        }
        .onChange(of: focusedCamera) { _, id in
            // Channel-flip feel: moving focus across the strip switches the
            // active stream live. selectCamera is a no-op when the id is
            // unchanged or the camera's URL isn't resolved yet.
            if let id { viewModel.selectCamera(id) }
        }
    }

    // MARK: - Dashboard Layout

    private var dashboardContent: some View {
        VStack(spacing: 0) {
            // Top bar — lean: city selector + clock only
            topBar
                .padding(.horizontal, 60)
                .padding(.top, 28)

            // Info row: Ramps (2/3) | Tide+Weather combined (1/3). Sized to the
            // row's natural height (no greedy GeometryReader) so the taller
            // tide/weather card can't overflow onto the day-timeline bar below.
            HStack(alignment: .top, spacing: 24) {
                rampGrid
                    .frame(maxWidth: .infinity)

                tideWeatherCard
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.33 }
            }
            .padding(.horizontal, 60)
            .padding(.top, 14)

            Spacer(minLength: 12)

            // Day-timeline bar — sun rhythm across the full width, above the cam
            DayTimelineBar(
                timeline: sunTimeline,
                nowFraction: nowFraction,
                errorMessage: viewModel.errorMessage
            )
            .padding(.horizontal, 60)
            .padding(.bottom, 12)

            // Panoramic beach cam banner (the hero)
            TVVideoPlayerView(
                url: viewModel.videoStreamURL,
                rebuildToken: viewModel.videoStreamGeneration,
                isPlaying: $viewModel.isVideoPlaying,
                onPlaybackFailure: { viewModel.refreshVideoStream() }
            )
            .padding(.horizontal, 60)
            .padding(.bottom, 6)

            // Coastline camera switcher across the bottom — pins placed
            // geographically along the coast
            if !viewModel.cameras.isEmpty {
                CoastlineRail(
                    cameras: viewModel.cameras,
                    selectedID: viewModel.selectedCameraID,
                    focusedCamera: $focusedCamera,
                    onSelect: { viewModel.selectCamera($0) }
                )
                .padding(.horizontal, 60)
                .padding(.bottom, 22)
            }
        }
    }

    // MARK: - Top Bar

    /// Lean header: the city selector on the left, the clock on the right. The
    /// day's sun rhythm and the ramp tallies now live in the timeline bar and the
    /// color-coded tiles, so the header stays out of the way.
    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Button {
                viewModel.nextCity()
            } label: {
                HStack(spacing: 8) {
                    Text(viewModel.currentCity)
                        .font(.system(size: 40, weight: .bold))
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.title3)
                        .opacity(0.6)
                }
            }
            .buttonStyle(FlatFocusButtonStyle(
                isFocused: cityFocused,
                cornerRadius: 12,
                horizontalPadding: 16,
                verticalPadding: 8
            ))
            .focused($cityFocused)
            // Pull the chip back so its padding doesn't shift the title's left edge.
            .padding(.leading, -16)

            Spacer()

            Text(currentTime)
                .font(.system(size: 38, weight: .light, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
    }

    // MARK: - Ramp Grid

    private var rampGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(viewModel.displayedRamps) { ramp in
                    TVRampTile(ramp: ramp)
                }
            }
        }
    }

    // MARK: - Combined Tide + Weather Card

    private var tideWeatherCard: some View {
        HStack(alignment: .top, spacing: 20) {
            tideColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 1)

            weatherColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .glassCard()
    }

    private var tideColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Tide", systemImage: "water.waves")

            if let tide = viewModel.tideInfo {
                HStack(spacing: 6) {
                    Image(systemName: tide.isRising ? "arrow.up.right" : "arrow.down.right")
                    Text(tide.isRising ? "Rising" : "Falling")
                }
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            }

            // Mini tide chart
            if let data = viewModel.tideChart, !data.hourly.isEmpty {
                Chart {
                    ForEach(data.hourly) { point in
                        AreaMark(
                            x: .value("Time", point.time),
                            y: .value("Height", point.height)
                        )
                        .foregroundStyle(.white.opacity(0.1))
                    }
                    ForEach(data.hourly) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Height", point.height)
                        )
                        .foregroundStyle(.white.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 4))
                    }
                    RuleMark(x: .value("Now", data.currentTime))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 4))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 52)
            }

            // Water temp — large
            if let temp = viewModel.tideInfo?.waterTempAvg {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.water")
                    Text("Water \(Int(temp))°")
                }
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            }

            // One detail line: next high/low tide
            if let next = nextTide {
                Text("Next \(next.label) · \(next.timeDisplay)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var weatherColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Weather", systemImage: "cloud.sun.fill")

            if let current = viewModel.weather?.current {
                Text(current.tempDisplay)
                    .font(.system(size: 56, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)

                if let desc = current.description {
                    Text(desc)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Label(current.windDisplay, systemImage: "wind")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            // One detail line: tomorrow's forecast
            if let tomorrow = tomorrowForecast {
                Text("\(tomorrow.shortName) \(tomorrow.tempDisplay)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
    }

    // MARK: - Derived Data

    /// The next upcoming high/low tide prediction.
    private var nextTide: TidePrediction? {
        guard let preds = viewModel.tideInfo?.predictions else { return nil }
        let now = Date()
        return preds.filter { $0.time > now }.min { $0.time < $1.time }
    }

    /// Tomorrow's daytime forecast (the second daytime period), for the one-line summary.
    private var tomorrowForecast: ForecastPeriod? {
        guard let forecast = viewModel.weather?.forecast else { return nil }
        let daytime = forecast.filter(\.isDaytime)
        return daytime.count > 1 ? daytime[1] : daytime.first
    }

    // MARK: - Clock & Sun

    private func startClock() {
        tick()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            tick()
        }
    }

    /// Updates the clock and the sun's altitude (driving the background), advances
    /// the timeline "now" marker, and rebuilds the day's sun timeline when the
    /// calendar day rolls over.
    private func tick() {
        let now = Date()
        let calendar = Self.easternCalendar

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

// MARK: - Flat Focus Button Style

/// A tvOS button style that fully replaces the system's frost-and-lift focus
/// treatment with a flat chip: a translucent fill and a hairline border that
/// brighten on focus, plus a tiny press dip. No scaling on focus, so focused
/// chips stay put instead of ballooning over their neighbors.
private struct FlatFocusButtonStyle: ButtonStyle {
    var isFocused: Bool
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 12
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(isFocused ? 0.26 : (isSelected ? 0.14 : 0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        .white.opacity(isFocused ? 1.0 : (isSelected ? 0.6 : 0)),
                        lineWidth: isFocused ? 2.5 : 2
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Glass Card Styling

/// Frosted-glass card surface — translucent material with a hairline highlight,
/// so cards read as floating over the sky rather than flat fills.
private struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - TV Subviews

/// Compact ramp tile for the TV grid — card with indicator + name on top, status below.
struct TVRampTile: View {
    let ramp: Ramp

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: indicator + name
            HStack(spacing: 8) {
                Image(systemName: ramp.category.tvIcon)
                    .font(.system(size: 30))
                    .foregroundStyle(ramp.category.tvColor)

                Text(ramp.rampName.titleCased)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            // Status text — full width
            Text(ramp.accessStatus.titleCased)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(ramp.category.tvColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard()
    }
}

// MARK: - Day Timeline Model

/// The sun's rhythm for a single day, precomputed for the timeline bar: the key
/// solar events as fractions (0…1) of the local day, plus formatted times. Built
/// once per day from `SolarCalculator`; the bar reads it every tick.
struct SunTimeline {
    struct Event {
        let fraction: Double   // 0…1 position along the 24-hour day
        let timeText: String   // e.g. "6:28 AM"
    }

    let civilDawn: Event?          // sun at -6° (ascending) — first light
    let sunrise: Event?            // sun at the horizon (ascending)
    let goldenMorningEnd: Event?   // sun at +6° (ascending) — golden hour ends
    let solarNoon: Event?          // sun's daily peak
    let goldenEveningStart: Event? // sun at +6° (descending) — golden hour begins
    let sunset: Event?             // sun at the horizon (descending)
    let civilDusk: Event?          // sun at -6° (descending) — last light

    init(day: Date, solar: SolarCalculator, calendar: Calendar, zone: TimeZone) {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = zone

        func event(_ date: Date?) -> Event? {
            guard let date else { return nil }
            return Event(
                fraction: SunTimeline.dayFraction(of: date, calendar: calendar),
                timeText: formatter.string(from: date)
            )
        }

        let events = solar.events(on: day, calendar: calendar)
        civilDawn = event(solar.crossing(altitude: -6, rising: true, on: day, calendar: calendar))
        sunrise = event(events.sunrise)
        goldenMorningEnd = event(solar.crossing(altitude: 6, rising: true, on: day, calendar: calendar))
        solarNoon = event(solar.solarNoon(on: day, calendar: calendar))
        goldenEveningStart = event(solar.crossing(altitude: 6, rising: false, on: day, calendar: calendar))
        sunset = event(events.sunset)
        civilDusk = event(solar.crossing(altitude: -6, rising: false, on: day, calendar: calendar))
    }

    /// Fraction (0…1) of the local calendar day represented by `date`.
    static func dayFraction(of date: Date, calendar: Calendar) -> Double {
        let start = calendar.startOfDay(for: date)
        return min(1, max(0, date.timeIntervalSince(start) / 86_400))
    }
}

// MARK: - Day Timeline Bar

/// Full-width day-rhythm bar: a 24-hour gradient from night through twilight,
/// golden hour, and daylight and back, with a marker for "now" beneath it, the
/// sunrise / solar-noon / sunset times labeled, and a live caption for the next
/// meaningful sun event.
struct DayTimelineBar: View {
    let timeline: SunTimeline?
    let nowFraction: Double
    let errorMessage: String?

    // Bar palette — independent of the sky background so the bar reads clearly
    // over any time-of-day gradient.
    private static let night = Color(red: 0.043, green: 0.098, blue: 0.176)
    private static let twilight = Color(red: 0.180, green: 0.200, blue: 0.420)
    private static let goldenLow = Color(red: 0.770, green: 0.440, blue: 0.120)
    private static let goldenHigh = Color(red: 0.950, green: 0.700, blue: 0.290)
    private static let day = Color(red: 0.750, green: 0.880, blue: 0.970)
    private static let noon = Color(red: 0.850, green: 0.930, blue: 0.990)
    private static let marker = Color(red: 1.0, green: 0.271, blue: 0.227)

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(LinearGradient(stops: gradientStops, startPoint: .leading, endPoint: .trailing))
                        .frame(height: 22)
                        .position(x: w / 2, y: 11)

                    ForEach(labeledEvents, id: \.name) { ev in
                        labelView(ev)
                            .position(x: clamp(CGFloat(ev.fraction) * w, 60, w - 60), y: 72)
                    }

                    markerView
                        .position(x: min(w, max(0, CGFloat(nowFraction) * w)), y: 11)
                        .animation(.easeInOut(duration: 1.0), value: nowFraction)
                }
            }
            .frame(height: 102)

            captionView
        }
    }

    // MARK: Bar gradient

    private var gradientStops: [Gradient.Stop] {
        guard let t = timeline,
              let dawn = t.civilDawn?.fraction,
              let rise = t.sunrise?.fraction,
              let gAM = t.goldenMorningEnd?.fraction,
              let noon = t.solarNoon?.fraction,
              let gPM = t.goldenEveningStart?.fraction,
              let set = t.sunset?.fraction,
              let dusk = t.civilDusk?.fraction
        else {
            return [
                .init(color: Self.night, location: 0),
                .init(color: Self.day, location: 0.5),
                .init(color: Self.night, location: 1),
            ]
        }

        var stops: [Gradient.Stop] = []
        func add(_ color: Color, _ location: Double) {
            stops.append(.init(color: color, location: min(1, max(0, location))))
        }
        add(Self.night, 0)
        add(Self.night, dawn)
        add(Self.twilight, dawn)
        add(Self.goldenLow, rise)
        add(Self.goldenHigh, (rise + gAM) / 2)
        add(Self.day, gAM)
        add(Self.noon, noon)
        add(Self.day, gPM)
        add(Self.goldenHigh, (gPM + set) / 2)
        add(Self.goldenLow, set)
        add(Self.twilight, set)
        add(Self.twilight, dusk)
        add(Self.night, dusk)
        add(Self.night, 1)
        return stops
    }

    // MARK: Marker

    private var markerView: some View {
        ZStack {
            Capsule()
                .fill(.white)
                .frame(width: 4, height: 34)
            Circle()
                .fill(Self.marker)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                .offset(y: 25)
        }
    }

    // MARK: Labels

    private struct Labeled { let name: String; let icon: String; let timeText: String; let fraction: Double }

    private var labeledEvents: [Labeled] {
        guard let t = timeline else { return [] }
        var out: [Labeled] = []
        if let e = t.sunrise { out.append(.init(name: "Sunrise", icon: "sunrise.fill", timeText: e.timeText, fraction: e.fraction)) }
        if let e = t.solarNoon { out.append(.init(name: "Solar noon", icon: "sun.max.fill", timeText: e.timeText, fraction: e.fraction)) }
        if let e = t.sunset { out.append(.init(name: "Sunset", icon: "sunset.fill", timeText: e.timeText, fraction: e.fraction)) }
        return out
    }

    private func labelView(_ ev: Labeled) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: ev.icon)
                    .font(.system(size: 22))
                Text(ev.timeText)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
            }
            Text(ev.name)
                .font(.system(size: 20, weight: .medium))
                .opacity(0.75)
        }
        .foregroundStyle(.white)
        .fixedSize()
    }

    // MARK: Caption

    private var captionView: some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: captionIcon)
                Text(captionText)
            }
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private enum Phase { case preDawn, dawn, morningGolden, day, eveningGolden, dusk, night }

    private var phase: Phase {
        guard let t = timeline, let rise = t.sunrise, let set = t.sunset else { return .day }
        let f = nowFraction
        if let d = t.civilDawn, f < d.fraction { return .preDawn }
        if f < rise.fraction { return .dawn }
        if let g = t.goldenMorningEnd, f < g.fraction { return .morningGolden }
        if let g = t.goldenEveningStart, f < g.fraction { return .day }
        if f < set.fraction { return .eveningGolden }
        if let d = t.civilDusk, f < d.fraction { return .dusk }
        return .night
    }

    private var captionIcon: String {
        switch phase {
        case .preDawn, .dawn: return "sunrise.fill"
        case .morningGolden: return "sun.max"
        case .day: return "sun.max.fill"
        case .eveningGolden: return "sunset.fill"
        case .dusk: return "moon.stars"
        case .night: return "moon.stars.fill"
        }
    }

    private var captionText: String {
        guard let t = timeline, let rise = t.sunrise, let set = t.sunset else { return "" }
        let f = nowFraction
        switch phase {
        case .preDawn, .dawn:
            return "Sunrise at \(rise.timeText)"
        case .morningGolden:
            if let g = t.goldenMorningEnd { return "Golden hour until \(g.timeText)" }
            return "Sunrise was \(rise.timeText)"
        case .day:
            let daylight = durationText(set.fraction - f)
            if let g = t.goldenEveningStart {
                return "Golden hour \(g.timeText) · \(daylight) of daylight left"
            }
            return "\(daylight) of daylight left"
        case .eveningGolden:
            return "Golden hour now · sunset \(set.timeText)"
        case .dusk:
            if let d = t.civilDusk { return "Sunset \(set.timeText) · dusk until \(d.timeText)" }
            return "Sunset was \(set.timeText)"
        case .night:
            return "Sunrise \(rise.timeText)"
        }
    }

    private func durationText(_ fractionSpan: Double) -> String {
        let totalMinutes = Int(max(0, fractionSpan) * 86_400 / 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(lo, value), max(lo, hi))
    }
}

// MARK: - Coastline Rail (camera switcher)

/// Camera switcher styled as a stretch of coastline: each camera is a pin placed
/// at its geographic position (north on the left, south on the right). The live
/// camera keeps a persistent ring + "Live" tag; the focused pin (wherever the
/// remote sits) pops a name pill above it. Moving focus channel-flips the stream;
/// clicking selects too.
struct CoastlineRail: View {
    let cameras: [Camera]
    let selectedID: String?
    @FocusState.Binding var focusedCamera: String?
    let onSelect: (String) -> Void

    /// Normalized coast position (0 = north / left, 1 = south / right), keyed by
    /// camera id. Hand-tuned from the real Volusia latitudes for legible spacing.
    private static let coastPosition: [String: Double] = [
        "ormond-by-the-sea": 0.06,
        "ormond-beach":      0.28,
        "dunlawton":         0.50,
        "ponce-inlet":       0.72,
        "nsb":               0.94,
    ]

    /// True when every camera has a mapped position; otherwise we even-space all
    /// of them (by roster order, which runs south→north) so a future or unknown
    /// camera still lands somewhere sensible and consistent.
    private var allMapped: Bool {
        cameras.allSatisfy { Self.coastPosition[$0.id] != nil }
    }

    private func position(for camera: Camera, index: Int) -> Double {
        if allMapped, let mapped = Self.coastPosition[camera.id] { return mapped }
        guard cameras.count > 1 else { return 0.5 }
        // Roster is south→north; place north (last) on the left to match the map.
        return 0.94 - 0.88 * Double(index) / Double(cameras.count - 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let rowCenterY: CGFloat = 41
            ZStack(alignment: .topLeading) {
                // North / south anchors
                Text("N")
                    .coastAnchor()
                    .position(x: 12, y: rowCenterY)
                Text("S")
                    .coastAnchor()
                    .position(x: w - 12, y: rowCenterY)

                // The coast line
                Capsule()
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.15), .white.opacity(0.32)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: w - 40, height: 2)
                    .position(x: w / 2, y: rowCenterY)

                // Pins
                ForEach(Array(cameras.enumerated()), id: \.element.id) { index, camera in
                    Button {
                        onSelect(camera.id)
                    } label: {
                        CoastPin(
                            name: camera.name,
                            isSelected: camera.id == selectedID,
                            isFocused: camera.id == focusedCamera,
                            isOffline: camera.url == nil
                        )
                    }
                    .buttonStyle(CoastPinButtonStyle())
                    .focused($focusedCamera, equals: camera.id)
                    .position(x: clamp(CGFloat(position(for: camera, index: index)) * w, 80, w - 80), y: rowCenterY)
                }
            }
        }
        .frame(height: 82)
        .focusSection()
        .animation(.easeOut(duration: 0.15), value: focusedCamera)
    }

    private func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(lo, value), max(lo, hi))
    }
}

/// Button style for coast pins that contributes **no focus chrome of its own** —
/// the pin draws all of its own focus/selection state (halo, name pill, ring).
/// Necessary because on tvOS `.buttonStyle(.plain)` still lets the system paint
/// its frosted focus "bulge"; supplying a custom ButtonStyle fully replaces it.
private struct CoastPinButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A single coastline camera pin: a dot on the coast line with its name below,
/// a name pill above when focused, and a persistent ring + "Live" tag when it is
/// the active stream.
private struct CoastPin: View {
    let name: String
    let isSelected: Bool
    let isFocused: Bool
    let isOffline: Bool

    private static let live = Color(red: 0.32, green: 0.68, blue: 1.0)
    private static let ring = Color(red: 0.12, green: 0.48, blue: 0.88)
    private static let pillText = Color(red: 0.05, green: 0.13, blue: 0.22)

    var body: some View {
        ZStack {
            if isFocused {
                Text(name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Self.pillText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white))
                    .fixedSize()
                    .offset(y: -30)
            }

            dot

            if !isFocused {
                Text(name)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isOffline ? 0.4 : (isSelected ? 1.0 : 0.7)))
                    .fixedSize()
                    .offset(y: 26)
            }

            if isSelected && !isOffline {
                Text("Live")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Self.live)
                    .offset(y: isFocused ? 24 : 44)
            }
        }
        .frame(width: 160, height: 82)
    }

    @ViewBuilder private var dot: some View {
        if isOffline {
            Circle()
                .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                .frame(width: 14, height: 14)
        } else if isFocused {
            ZStack {
                Circle().fill(.white.opacity(0.28)).frame(width: 30, height: 30)
                Circle().fill(.white).frame(width: 16, height: 16)
            }
        } else if isSelected {
            ZStack {
                Circle().fill(Self.ring.opacity(0.35)).frame(width: 26, height: 26)
                Circle().fill(.white).frame(width: 15, height: 15)
                Circle().stroke(Self.ring, lineWidth: 3).frame(width: 15, height: 15)
            }
        } else {
            Circle().fill(.white.opacity(0.55)).frame(width: 11, height: 11)
        }
    }
}

private extension Text {
    /// Styling for the small N / S coastline anchors.
    func coastAnchor() -> some View {
        self.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
    }
}

#Preview {
    ContentView()
}
