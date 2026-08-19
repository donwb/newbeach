import SwiftUI
import BeachStatus

// MARK: - Day Timeline Model

/// The sun's rhythm for a single day, precomputed for the ribbon: the key
/// solar events as fractions (0…1) of the local day, plus formatted times.
/// Built once per day from `SolarCalculator`; the ribbon reads it every tick.
///
/// Crossings at −18/−9/−6° cover the three twilights; +6/+20/+34 mark the
/// golden-hour end and the mid-morning color steps that the sky palette also
/// uses, so the ribbon's gradient tracks the board's background exactly.
struct SunTimeline {
    struct Event {
        let fraction: Double   // 0…1 position along the 24-hour day
        let timeText: String   // e.g. "6:28 AM"
    }

    // Rising
    let astronomicalDawn: Event?   // −18° ↑
    let nauticalDawn: Event?       // −9° ↑
    let civilDawn: Event?          // −6° ↑ — first light
    let sunrise: Event?
    let goldenMorningEnd: Event?   // +6° ↑
    let morningFull: Event?        // +20° ↑
    let lateMorning: Event?        // +34° ↑
    let solarNoon: Event?
    // Falling
    let earlyAfternoonEnd: Event?  // +34° ↓
    let afternoonStart: Event?     // +20° ↓
    let goldenEveningStart: Event? // +6° ↓
    let sunset: Event?
    let civilDusk: Event?          // −6° ↓ — last light
    let nauticalDusk: Event?       // −9° ↓
    let astronomicalDusk: Event?   // −18° ↓
    /// Tomorrow's sunrise — the night caption points forward to it instead of
    /// repeating today's (already shown in the ribbon's left label). Its
    /// fraction is relative to tomorrow and never placed on today's gradient.
    let tomorrowSunrise: Event?

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
        func crossing(_ altitude: Double, rising: Bool) -> Event? {
            event(solar.crossing(altitude: altitude, rising: rising, on: day, calendar: calendar))
        }

        let events = solar.events(on: day, calendar: calendar)
        astronomicalDawn = crossing(-18, rising: true)
        nauticalDawn = crossing(-9, rising: true)
        civilDawn = crossing(-6, rising: true)
        sunrise = event(events.sunrise)
        goldenMorningEnd = crossing(6, rising: true)
        morningFull = crossing(20, rising: true)
        lateMorning = crossing(34, rising: true)
        solarNoon = event(solar.solarNoon(on: day, calendar: calendar))
        earlyAfternoonEnd = crossing(34, rising: false)
        afternoonStart = crossing(20, rising: false)
        goldenEveningStart = crossing(6, rising: false)
        sunset = event(events.sunset)
        civilDusk = crossing(-6, rising: false)
        nauticalDusk = crossing(-9, rising: false)
        astronomicalDusk = crossing(-18, rising: false)

        if let nextDay = calendar.date(byAdding: .day, value: 1, to: day) {
            tomorrowSunrise = event(solar.events(on: nextDay, calendar: calendar).sunrise)
        } else {
            tomorrowSunrise = nil
        }
    }

    /// Fraction (0…1) of the local calendar day represented by `date`.
    static func dayFraction(of date: Date, calendar: Calendar) -> Double {
        let start = calendar.startOfDay(for: date)
        return min(1, max(0, date.timeIntervalSince(start) / 86_400))
    }
}

// MARK: - Daylight Band

/// The daylight band of design v3: a flat 14pt strip — a 24-hour gradient
/// through the sky phases — with a white now marker standing proud of it,
/// and three captions beneath: sunrise, the live middle caption, sunset.
/// After sunset the end labels swap (sunset left, tomorrow's sunrise right)
/// because that is the order the night now reads in.
struct SunRibbon: View {
    let timeline: SunTimeline?
    let nowFraction: Double
    /// Stale board: sun facts are computed locally and stay trustworthy —
    /// the caption says so.
    let isStale: Bool

    @Environment(\.skyPalette) private var sky

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(LinearGradient(stops: gradientStops, startPoint: .leading, endPoint: .trailing))
                        .frame(width: w, height: 14)
                        .offset(y: 7)

                    // The now marker: a white rule standing 7pt proud of the
                    // strip on both sides.
                    Rectangle()
                        .fill(.white)
                        .frame(width: 4, height: 28)
                        .position(x: markerX(w), y: 14)
                        .animation(.easeInOut(duration: 1.0), value: nowFraction)
                }
            }
            .frame(height: 28)

            HStack {
                Text(leadingLabel)
                Spacer()
                Text(caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(trailingLabel)
            }
            .font(.system(size: 22))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.top, 14)
        }
    }

    private func markerX(_ width: CGFloat) -> CGFloat {
        min(width - 2, max(2, CGFloat(nowFraction) * width))
    }

    /// True from sunset until midnight — the stretch where the night reads
    /// sunset-first and points at tomorrow's sunrise.
    private var isEveningNight: Bool {
        guard let set = timeline?.sunset else { return false }
        return nowFraction >= set.fraction
    }

    // MARK: Gradient

    // Phase top-colors from the sky palette, placed at the day's real solar
    // event fractions — never hard-coded positions.
    private var gradientStops: [Gradient.Stop] {
        guard let t = timeline else {
            return [
                .init(color: Color(boardHex: 0x070A14), location: 0),
                .init(color: Color(boardHex: 0x0E7FA8), location: 0.5),
                .init(color: Color(boardHex: 0x070A14), location: 1),
            ]
        }

        var stops: [Gradient.Stop] = [.init(color: Color(boardHex: 0x070A14), location: 0)]
        func add(_ hex: UInt32, _ event: SunTimeline.Event?) {
            guard let event else { return }
            let location = min(1, max(0, event.fraction))
            if let last = stops.last, location <= last.location { return }
            stops.append(.init(color: Color(boardHex: hex), location: location))
        }
        add(0x080C1A, t.astronomicalDawn)
        add(0x0C1230, t.nauticalDawn)
        add(0x142046, t.civilDawn)
        add(0x1B2A52, t.sunrise)
        add(0x17456B, t.goldenMorningEnd)
        add(0x0E6E8C, t.morningFull)
        add(0x0E779A, t.lateMorning)
        add(0x0E7FA8, t.solarNoon)
        add(0x0F7294, t.earlyAfternoonEnd)
        add(0x10657F, t.afternoonStart)
        add(0x145066, t.goldenEveningStart)
        add(0x123A52, t.sunset)
        add(0x0E2840, t.civilDusk)
        add(0x0A1228, t.nauticalDusk)
        add(0x080D1C, t.astronomicalDusk)
        stops.append(.init(color: Color(boardHex: 0x070A14), location: 1))
        return stops
    }

    // MARK: Labels

    private var leadingLabel: String {
        if isEveningNight {
            guard let e = timeline?.sunset else { return "" }
            return "Sunset \(e.timeText)"
        }
        guard let e = timeline?.sunrise else { return "" }
        return "Sunrise \(e.timeText)"
    }

    private var trailingLabel: String {
        if isEveningNight {
            guard let e = timeline?.tomorrowSunrise else { return "" }
            return "Sunrise \(e.timeText)"
        }
        guard let e = timeline?.sunset else { return "" }
        return "Sunset \(e.timeText)"
    }

    // MARK: Caption

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

    private var caption: String {
        if isStale { return "Sun data local — unaffected" }
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
        case .dusk, .night:
            // The sky palette's phase name ("Civil dusk", "Night") narrates
            // the dark hours, pointing at when the light comes back.
            if let tomorrow = t.tomorrowSunrise {
                return "\(sky.phaseName) · dark until \(tomorrow.timeText)"
            }
            return "\(sky.phaseName) · sunrise \(rise.timeText)"
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
}

#if DEBUG
#Preview {
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        SunRibbon(timeline: PreviewFixtures.sunTimeline, nowFraction: 0.56, isStale: false)
            .padding(.horizontal, 60)
    }
}

#Preview("Stale") {
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        SunRibbon(timeline: PreviewFixtures.sunTimeline, nowFraction: 0.56, isStale: true)
            .padding(.horizontal, 60)
    }
}
#endif
