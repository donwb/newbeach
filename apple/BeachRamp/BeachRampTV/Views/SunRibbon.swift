import SwiftUI
import BeachStatus

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
