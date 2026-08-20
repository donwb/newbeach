import SwiftUI
import BeachStatus

/// The Ramp detail pull surface: title block, status band, then one
/// three-column row — today as a bar, the tide against this ramp, the
/// 48-hour log. Open is plain type-white and closed is red; no green
/// anywhere (red/green is the least reliable distinction at ten feet).
struct RampDetailSurface: View {
    let ramp: Ramp
    /// "RAMP 02 · NEW SMYRNA BEACH"
    let kicker: String
    /// The surf line verbatim, italic beside the name.
    let surfSentence: String?
    /// The ramp's outlook headline verbatim ("Could close around the 4pm
    /// high tide"). Nil renders nothing.
    let prediction: String?
    let intervals: RampIntervals?
    let tideDirection: String?
    let tideChart: TideChartData?
    let now: Date

    private var isClosed: Bool { ramp.category == .closed }

    private static let eastern = TimeZone(identifier: "America/New_York")!
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern
        return cal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBlock
            statusBand
            HStack(alignment: .top, spacing: 0) {
                todayColumn
                    .padding(.trailing, 40)
                    .frame(width: 480, alignment: .topLeading)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(TVInk.rule).frame(width: 2)
                    }
                tideColumn
                    .padding(.horizontal, 40)
                    .frame(width: 790, alignment: .topLeading)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(TVInk.rule).frame(width: 2)
                    }
                logColumn
                    .padding(.leading, 40)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .padding(EdgeInsets(top: 20, leading: TVMetrics.sidePad,
                            bottom: 30, trailing: TVMetrics.sidePad))
    }

    // MARK: - Title + status

    private var titleBlock: some View {
        HStack(alignment: .bottom, spacing: 48) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker).tvLabel(24, color: TVInk.label)
                HStack(alignment: .firstTextBaseline, spacing: 26) {
                    Text(ramp.rampDisplayName)
                        .tv(60, .extraBold, tracking: -0.035)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(TVInk.type)
                    if let surfSentence {
                        Text(surfSentence)
                            .tv(28)
                            .italic()
                            .lineLimit(1)
                            .foregroundStyle(TVInk.type.opacity(0.6))
                    }
                }
            }
            Spacer(minLength: 0)
            SurfaceBackHint()
        }
    }

    private var statusBand: some View {
        HStack(alignment: .center, spacing: 48) {
            HStack(spacing: 18) {
                Rectangle()
                    .fill(isClosed ? TVInk.closed : TVInk.type)
                    .frame(width: 12, height: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(tvStatusWord(ramp.accessStatus))
                        .tv(42, .extraBold, tracking: -0.02)
                        .lineLimit(1)
                        .foregroundStyle(isClosed ? TVInk.closed : TVInk.type)
                    if let since = ramp.statusSince {
                        Text("since \(SinceFormatter.string(from: since))")
                            .tv(24)
                            .foregroundStyle(TVInk.typeDim)
                    }
                }
            }
            Spacer(minLength: 0)
            if let prediction {
                Text(prediction)
                    .tv(32, .semiBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(TVInk.type)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
        .overlay(Rectangle().strokeBorder(TVInk.type.opacity(0.34), lineWidth: 2))
    }

    // MARK: - Column 1: today

    private var todayColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today, midnight to midnight")
                .tvLabel(24, color: TVInk.sand)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(TVInk.rule).frame(height: 2)
                }
            TodayBandView(intervals: todayIntervals, now: now, calendar: Self.calendar)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(todayTransitions.prefix(5), id: \.time) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(Self.clock(event.time))
                            .tv(24, .bold).monospacedDigit()
                            .foregroundStyle(TVInk.type)
                            .frame(width: 130, alignment: .leading)
                        Text(event.label)
                            .tv(24)
                            .lineLimit(1)
                            .foregroundStyle(TVInk.typeDim)
                    }
                }
            }
        }
    }

    // MARK: - Column 2: tide

    private var tideColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tide against this ramp").tvLabel(24, color: TVInk.sand)
                Spacer(minLength: 0)
                if let tideDirection {
                    Text(tideDirection)
                        .tv(24)
                        .foregroundStyle(TVInk.typeDim)
                }
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(TVInk.rule).frame(height: 2)
            }

            if let chart = tideChart, !curvePoints(chart).isEmpty {
                TideCurveShapeView(
                    points: curvePoints(chart),
                    range: todayRange,
                    height: 170,
                    threshold: nil,
                    strokeWidth: 3,
                    strokeColor: TVInk.type,
                    fillColor: TVInk.type.opacity(0.13),
                    nowLineColor: TVInk.type
                )
                .padding(.top, 8)
            } else {
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 16) {
                ForEach(todayTurns, id: \.time) { turn in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(turn.kind).tvLabel()
                        Text(Self.clock(turn.time))
                            .tv(30, .extraBold).monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(TVInk.type)
                        Text(turn.height)
                            .tv(24)
                            .foregroundStyle(TVInk.type.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .overlay(alignment: .top) {
                        Rectangle().fill(TVInk.rule).frame(height: 2)
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Column 3: 48-hour log

    private var logColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Last 48 hours")
                .tvLabel(24, color: TVInk.sand)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(TVInk.rule).frame(height: 2)
                }
            if let intervals {
                RampEventLogView(intervals: intervals, now: now, calendar: Self.calendar)
                    .padding(.top, 2)
            } else {
                Text("Loading history…")
                    .tv(24)
                    .foregroundStyle(TVInk.inactive)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - Data shaping

    private var todayRange: ClosedRange<Date> {
        let start = Self.calendar.startOfDay(for: now)
        let end = Self.calendar.date(byAdding: .day, value: 1, to: start)!
        return start...end
    }

    private func curvePoints(_ chart: TideChartData) -> [TideCurve.Point] {
        TideCurve.points(extremes: chart.highLow, in: todayRange)
    }

    private var todayTurns: [(kind: String, time: Date, height: String)] {
        guard let chart = tideChart else { return [] }
        return chart.highLow
            .filter { todayRange.contains($0.time) }
            .prefix(4)
            .map { p in
                (kind: p.type == "H" ? "High" : "Low",
                 time: p.time,
                 height: p.height.map { String(format: "%.1f ft", $0) } ?? "—")
            }
    }

    private var todayIntervals: [RampInterval] {
        guard let intervals else { return [] }
        let start = Self.calendar.startOfDay(for: now)
        return intervals.intervals
            .filter { $0.end > start && $0.start < now }
            .sorted { $0.start < $1.start }
    }

    private var todayTransitions: [(time: Date, label: String)] {
        let start = Self.calendar.startOfDay(for: now)
        return todayIntervals.map { interval in
            (time: max(interval.start, start), label: tvStatusWord(interval.status))
        }
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = eastern
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

/// The midnight-to-midnight bar: proportional segments up to "now" (closed
/// red, open white, limited dimmed white), the rest of the day left as
/// track, and a tick marking now.
struct TodayBandView: View {
    let intervals: [RampInterval]
    let now: Date
    let calendar: Calendar

    var body: some View {
        GeometryReader { geo in
            let dayStart = calendar.startOfDay(for: now)
            let daySeconds: TimeInterval = 24 * 3600
            ZStack(alignment: .topLeading) {
                Rectangle().fill(TVInk.track)
                ForEach(Array(intervals.enumerated()), id: \.offset) { _, interval in
                    let s = max(0, interval.start.timeIntervalSince(dayStart) / daySeconds)
                    let e = min(1, min(interval.end, now).timeIntervalSince(dayStart) / daySeconds)
                    if e > s {
                        Rectangle()
                            .fill(segmentColor(interval))
                            .frame(width: geo.size.width * (e - s))
                            .offset(x: geo.size.width * s)
                    }
                }
                let nowX = min(1, max(0, now.timeIntervalSince(dayStart) / daySeconds))
                Rectangle()
                    .fill(TVInk.type)
                    .frame(width: 4, height: 32)
                    .offset(x: geo.size.width * nowX - 2, y: -7)
            }
        }
        .frame(height: 18)
        .padding(.top, 7)
    }

    private func segmentColor(_ interval: RampInterval) -> Color {
        switch interval.statusCategory {
        case .open: TVInk.type
        case .limited: TVInk.type.opacity(0.55)
        case .closed: TVInk.closed
        }
    }
}

/// The last-48-hours event log: each interval start is an event, newest
/// first. Times relative-date: today plain, yesterday "Yest", older "Aug 18".
struct RampEventLogView: View {
    let intervals: RampIntervals
    let now: Date
    let calendar: Calendar

    private var events: [(time: Date, label: String)] {
        intervals.intervals
            .sorted { $0.start > $1.start }
            .map { (time: $0.start, label: tvStatusWord($0.status)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(events.prefix(7), id: \.time) { event in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(timeLabel(event.time))
                        .tv(26).monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(TVInk.typeDim)
                        .frame(width: 190, alignment: .leading)
                    Text(event.label)
                        .tv(26, .bold)
                        .lineLimit(1)
                        .foregroundStyle(TVInk.type)
                }
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(TVInk.ruleHair).frame(height: 1)
                }
            }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return RampDetailSurface.clock(date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yest " + RampDetailSurface.clock(date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

#if DEBUG
#Preview("Ramp detail", traits: .fixedLayout(width: 1920, height: 630)) {
    RampDetailSurface(
        ramp: PreviewFixtures.openRamps[1],
        kicker: "Ramp 02 · New Smyrna Beach",
        surfSentence: "Pretty much flat out there",
        prediction: "Could close around the 4pm high tide",
        intervals: PreviewFixtures.intervals,
        tideDirection: "Rising",
        tideChart: PreviewFixtures.tideChart,
        now: Date()
    )
    .background(TVInk.ground)
}
#endif
