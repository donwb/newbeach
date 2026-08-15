import SwiftUI
import WidgetKit
import BeachStatus

// MARK: - Ground container

/// Widgets sit on the same sun-following ground as the app, veil and all.
/// The shell keeps the system corner radius; everything inside is square.
struct WidgetGround<Content: View>: View {
    let entry: BoardEntry
    @ViewBuilder let content: (GroundState) -> Content

    var body: some View {
        let ground = entry.ground
        content(ground)
            .environment(\.ground, ground)
            .containerBackground(for: .widget) {
                ZStack {
                    ground.skyGradient
                    ground.veil
                }
            }
    }
}

// MARK: - The five-square strip

/// One square per ramp in city order, in the field colours — a bar chart of
/// the day at a glance. Gap tightens past five ramps.
struct FiveSquareStrip: View {
    let ramps: [Ramp]
    let isDay: Bool
    var height: CGFloat = 10

    var body: some View {
        HStack(spacing: ramps.count > 5 ? 2 : 3) {
            ForEach(ramps) { ramp in
                Rectangle()
                    .fill(fill(for: ramp))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func fill(for ramp: Ramp) -> Color {
        let field = StatusField.field(for: ramp.category, isDay: isDay)
        // The open card is white-on-veil; on the strip open reads as the
        // green mark instead so the chart stays a chart.
        return ramp.category == .open ? field.mark : field.fill
    }

    private var label: String {
        let open = ramps.filter { $0.category == .open }.count
        return "\(open) of \(ramps.count) ramps open"
    }
}

// MARK: - Small

struct SmallWidgetView: View {
    let entry: BoardEntry

    var body: some View {
        WidgetGround(entry: entry) { ground in
            let t = ground.tokens
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.cityName.uppercased())
                    .font(.archivo(9, weight: .bold))
                    .tracking(9 * ArchivoTracking.kicker)
                    .foregroundStyle(t.ink2)
                    .lineLimit(1)
                FiveSquareStrip(ramps: entry.ramps, isDay: ground.isDay)
                Spacer(minLength: 0)
                if let solo = entry.soloRamp {
                    soloBlock(solo, tokens: t, ground: ground)
                } else {
                    Text("\(entry.openCount) open")
                        .font(.archivo(38, weight: .extraBold))
                        .monospacedDigit()
                        .foregroundStyle(t.ink)
                    Text(exceptionLine)
                        .font(.archivo(12, weight: .bold))
                        .foregroundStyle(t.ink)
                        .lineLimit(2)
                }
                Text(SinceFormatter.clock(entry.date))
                    .font(.archivo(11))
                    .monospacedDigit()
                    .foregroundStyle(t.ink2)
            }
        }
    }

    @ViewBuilder
    private func soloBlock(_ ramp: Ramp, tokens t: TokenSet, ground: GroundState) -> some View {
        let field = StatusField.field(for: ramp.category, isDay: ground.isDay)
        Text(ramp.shortDisplayName)
            .font(.archivo(15, weight: .extraBold))
            .foregroundStyle(t.ink)
            .lineLimit(2)
        HStack(spacing: 6) {
            Rectangle().fill(field.mark).frame(width: 8, height: 16)
            Text(statusWord(ramp))
                .font(.archivo(20, weight: .extraBold))
                .foregroundStyle(t.ink)
        }
    }

    private var exceptionLine: String {
        let exceptions = entry.ramps.filter { $0.category != .open }
        switch exceptions.count {
        case 0: return "All open"
        case 1: return "\(exceptions[0].shortDisplayName) \(statusWord(exceptions[0]).lowercased())"
        default: return "\(exceptions.count) not open"
        }
    }
}

// MARK: - Medium

struct MediumWidgetView: View {
    let entry: BoardEntry

    var body: some View {
        WidgetGround(entry: entry) { ground in
            let t = ground.tokens
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(entry.cityName.uppercased())
                            .font(.archivo(9, weight: .bold))
                            .tracking(9 * ArchivoTracking.kicker)
                            .foregroundStyle(t.ink2)
                            .lineLimit(1)
                        Text("· \(SinceFormatter.clock(entry.date))")
                            .font(.archivo(9))
                            .monospacedDigit()
                            .foregroundStyle(t.ink2)
                    }
                    FiveSquareStrip(ramps: entry.ramps, isDay: ground.isDay)
                    verdictBlock(tokens: t)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(t.rule2).frame(width: 1)

                tideRail(tokens: t)
                    .frame(width: 108)
            }
        }
    }

    @ViewBuilder
    private func verdictBlock(tokens t: TokenSet) -> some View {
        let verdict = entry.verdict
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(verdictColor(verdict.category))
                .frame(width: 8, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.headline)
                    .font(.archivo(19, weight: .extraBold))
                    .tracking(19 * ArchivoTracking.headline)
                    .foregroundStyle(t.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                if let solo = entry.soloRamp, let since = solo.statusSince {
                    Text("since \(SinceFormatter.string(from: since, now: entry.date))")
                        .font(.archivo(11))
                        .foregroundStyle(t.ink2)
                } else if let since = latestChange {
                    Text("since \(SinceFormatter.string(from: since, now: entry.date))")
                        .font(.archivo(11))
                        .foregroundStyle(t.ink2)
                }
            }
        }
    }

    private var latestChange: Date? {
        entry.ramps.compactMap(\.statusSince).max()
    }

    @ViewBuilder
    private func tideRail(tokens t: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tide".uppercased())
                .font(.archivo(9, weight: .bold))
                .tracking(9 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)
            Text(tideValue)
                .font(.archivo(22, weight: .extraBold))
                .monospacedDigit()
                .foregroundStyle(t.ink)
            if let tide = entry.tide {
                Text(tide.isRising ? "Rising" : "Falling")
                    .font(.archivo(11))
                    .foregroundStyle(t.ink2)
            }
            Spacer(minLength: 2)
            sparkline
            if let next = nextExtreme {
                Text("\(next.label) \(SinceFormatter.clock(next.time))")
                    .font(.archivo(11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(t.ink)
            }
        }
    }

    private var tideValue: String {
        guard let chart = entry.tideChart,
              let point = chart.hourly.min(by: {
                  abs($0.time.timeIntervalSince(entry.date)) < abs($1.time.timeIntervalSince(entry.date))
              }) else { return "—" }
        return String(format: "%.1f ft", point.height)
    }

    private var nextExtreme: TidePrediction? {
        entry.tide.flatMap { VerdictBuilder.nextExtreme(in: $0, after: entry.date) }
    }

    @ViewBuilder
    private var sparkline: some View {
        if let chart = entry.tideChart {
            let window = entry.date.addingTimeInterval(-3600)...entry.date.addingTimeInterval(11 * 3600)
            let points = TideCurve.points(extremes: chart.highLow, in: window)
            if points.count >= 2 {
                TideCurveShapeView(points: points, range: window, height: 26)
            }
        }
    }
}

// MARK: - Large

struct LargeWidgetView: View {
    let entry: BoardEntry

    var body: some View {
        WidgetGround(entry: entry) { ground in
            let t = ground.tokens
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.cityName.uppercased())
                        .font(.archivo(9, weight: .bold))
                        .tracking(9 * ArchivoTracking.kicker)
                        .foregroundStyle(t.ink2)
                    Spacer()
                    Text(SinceFormatter.clock(entry.date))
                        .font(.archivo(11))
                        .monospacedDigit()
                        .foregroundStyle(t.ink2)
                }

                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(verdictColor(entry.verdict.category))
                        .frame(width: 8, height: 30)
                    Text(entry.verdict.headline)
                        .font(.archivo(23, weight: .extraBold))
                        .tracking(23 * ArchivoTracking.headline)
                        .foregroundStyle(t.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                Rectangle().fill(t.rule).frame(height: 2)

                if entry.ramps.count > 10 {
                    // Beyond ten, a count-only summary beats an unreadable list.
                    Text("\(entry.openCount) of \(entry.ramps.count) ramps open")
                        .font(.archivo(15, weight: .extraBold))
                        .foregroundStyle(t.ink)
                    Spacer(minLength: 0)
                } else if entry.ramps.count > 5 {
                    twoColumnList(tokens: t)
                    Spacer(minLength: 0)
                } else {
                    rampList(tokens: t)
                    Spacer(minLength: 0)
                }

                Rectangle().fill(t.rule).frame(height: 2)

                HStack(alignment: .center, spacing: 10) {
                    Text(tideReadout)
                        .font(.archivo(15, weight: .extraBold))
                        .monospacedDigit()
                        .foregroundStyle(t.ink)
                    sparkline
                }
                .frame(height: 30)
            }
        }
    }

    private func rampList(tokens t: TokenSet) -> some View {
        VStack(spacing: 0) {
            ForEach(entry.ramps) { ramp in
                rampRow(ramp, nameSize: 15, tokens: t)
                    .frame(minHeight: 30)
            }
        }
    }

    private func twoColumnList(tokens t: TokenSet) -> some View {
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(entry.ramps) { ramp in
                rampRow(ramp, nameSize: 11, markSize: CGSize(width: 6, height: 16), tokens: t)
                    .frame(minHeight: 34)
            }
        }
    }

    private func rampRow(_ ramp: Ramp, nameSize: CGFloat,
                         markSize: CGSize = CGSize(width: 8, height: 18),
                         tokens t: TokenSet) -> some View {
        let field = StatusField.field(for: ramp.category, isDay: entry.ground.isDay)
        return HStack(spacing: 8) {
            Text(ramp.shortDisplayName)
                .font(.archivo(nameSize, weight: .extraBold))
                .foregroundStyle(t.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 4)
            Rectangle()
                .fill(ramp.category == .open ? field.mark : field.fill)
                .frame(width: markSize.width, height: markSize.height)
            Text(statusWord(ramp))
                .font(.archivo(nameSize == 11 ? 10 : 12, weight: .extraBold))
                .foregroundStyle(t.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var tideReadout: String {
        guard let chart = entry.tideChart,
              let point = chart.hourly.min(by: {
                  abs($0.time.timeIntervalSince(entry.date)) < abs($1.time.timeIntervalSince(entry.date))
              }) else { return "Tide —" }
        let direction = entry.tide.map { $0.isRising ? "rising" : "falling" } ?? ""
        return String(format: "Tide %.1f ft %@", point.height, direction)
    }

    @ViewBuilder
    private var sparkline: some View {
        if let chart = entry.tideChart {
            let window = entry.date.addingTimeInterval(-3600)...entry.date.addingTimeInterval(11 * 3600)
            let points = TideCurve.points(extremes: chart.highLow, in: window)
            if points.count >= 2 {
                TideCurveShapeView(points: points, range: window, height: 26)
            }
        }
    }
}

// MARK: - Lock Screen accessories

/// These render monochrome — the system throws colour away — so status reads
/// as fill and weight, never hue.
struct AccessoryCircularView: View {
    let entry: BoardEntry

    var body: some View {
        ZStack {
            Gauge(value: Double(entry.openCount), in: 0...Double(max(entry.ramps.count, 1))) {
                Text("OPEN")
            } currentValueLabel: {
                VStack(spacing: -1) {
                    Text("\(entry.openCount)/\(entry.ramps.count)")
                        .font(.archivo(16, weight: .extraBold))
                        .monospacedDigit()
                    Text("OPEN")
                        .font(.archivo(8, weight: .bold))
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityLabel("\(entry.openCount) of \(entry.ramps.count) ramps open")
    }
}

struct AccessoryRectangularView: View {
    let entry: BoardEntry

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.white).frame(width: 5, height: 52)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.archivo(15, weight: .extraBold))
                    .lineLimit(1)
                Text(secondLine)
                    .font(.archivo(11))
                    .opacity(0.72)
                if let tideLine {
                    Text(tideLine)
                        .font(.archivo(11))
                        .monospacedDigit()
                        .opacity(0.72)
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var exceptions: [Ramp] { entry.ramps.filter { $0.category != .open } }

    private var headline: String {
        if let first = exceptions.first, exceptions.count == 1 {
            return "\(first.shortDisplayName) \(statusWord(first).lowercased())"
        }
        return "\(entry.openCount) of \(entry.ramps.count) open"
    }

    private var secondLine: String {
        exceptions.count == 1 ? "\(entry.openCount) others open"
                              : "\(exceptions.count) not open"
    }

    private var tideLine: String? {
        guard let chart = entry.tideChart, let tide = entry.tide,
              let point = chart.hourly.min(by: {
                  abs($0.time.timeIntervalSince(entry.date)) < abs($1.time.timeIntervalSince(entry.date))
              }) else { return nil }
        return String(format: "Tide %.1f ft %@", point.height, tide.isRising ? "↑" : "↓")
    }
}

struct AccessoryInlineView: View {
    let entry: BoardEntry

    var body: some View {
        Text(line)
            .containerBackground(for: .widget) { Color.clear }
    }

    private var line: String {
        let exceptions = entry.ramps.filter { $0.category != .open }
        var text = "\(entry.openCount) of \(entry.ramps.count) ramps open"
        if exceptions.count == 1 {
            text += " · \(exceptions[0].shortDisplayName) \(statusWord(exceptions[0]).lowercased())"
        }
        return text
    }
}

// MARK: - Shared helpers

func statusWord(_ ramp: Ramp) -> String {
    switch ramp.category {
    case .open: "Open"
    case .limited: "Limited"
    case .closed: "Closed"
    }
}

func verdictColor(_ category: StatusCategory) -> Color {
    switch category {
    case .open: Color(red: 0x0A / 255, green: 0x7A / 255, blue: 0x42 / 255)
    case .limited: Color(red: 0xF5 / 255, green: 0xA2 / 255, blue: 0x14 / 255)
    case .closed: Color(red: 0xD2 / 255, green: 0x2B / 255, blue: 0x18 / 255)
    }
}
