import SwiftUI
import Charts
import BeachStatus

/// Full-screen tide detail: cosine-interpolated day curve with a now line,
/// and the day's four extremes below.
struct TideDetailOverlay: View {
    let tide: TideInfo?
    let stationID: String
    let onClose: () -> Void

    private var now: Date { Date() }

    private var eastern: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    var body: some View {
        OverlayScaffold(
            kicker: "Tide · Ponce Inlet",
            title: tide?.isRising == true ? "Rising" : "Dropping",
            rightLine: nextExtremeLine,
            footnote: "NOAA station \(stationID) · predictions, not observations · press Menu to close",
            onClose: onClose
        ) {
            chart
                .frame(height: 340)
                .padding(.top, 24)

            extremesRow
                .padding(.top, 30)
        }
    }

    private var nextExtremeLine: String? {
        guard let tide, let next = VerdictBuilder.nextExtreme(in: tide, after: now) else { return nil }
        let inText = VerdictBuilder.durationText(next.time.timeIntervalSince(now))
        return "Next \(next.label.lowercased()) \(SinceFormatter.clock(next.time)) · in \(inText)"
    }

    // MARK: Chart

    private var curvePoints: [TideCurve.Point] {
        guard let extremes = tide?.predictions else { return [] }
        let start = eastern.startOfDay(for: now)
        let end = start.addingTimeInterval(86_400)
        return TideCurve.points(extremes: extremes, in: start...end)
    }

    @ViewBuilder private var chart: some View {
        let points = curvePoints
        if points.isEmpty {
            Rectangle()
                .fill(.white.opacity(0.04))
                .overlay {
                    Text("Tide curve unavailable")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.5))
                }
        } else {
            Chart {
                ForEach(points, id: \.time) { point in
                    AreaMark(
                        x: .value("Time", point.time),
                        y: .value("Height", point.height)
                    )
                    .foregroundStyle(.white.opacity(0.12))
                }
                ForEach(points, id: \.time) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Height", point.height)
                    )
                    .foregroundStyle(.white)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.white.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(StatusCategory.limited.statusColor)
                    .lineStyle(StrokeStyle(lineWidth: 4))
            }
            .chartYScale(domain: -0.5...3.2)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
    }

    // MARK: Extremes

    private var extremesRow: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(todaysExtremes, id: \.time) { extreme in
                VStack(alignment: .leading, spacing: 4) {
                    Rectangle()
                        .fill(BoardColor.ruleStrong)
                        .frame(height: 2)
                    Text(extreme.label)
                        .kickerStyle()
                        .padding(.top, 14)
                    Text(SinceFormatter.clock(extreme.time))
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                    Text(extreme.heightDisplay ?? " ")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var todaysExtremes: [TidePrediction] {
        (tide?.predictions ?? []).filter {
            eastern.isDate($0.time, inSameDayAs: now)
        }
    }
}

#Preview {
    TideDetailOverlay(tide: PreviewFixtures.tide, stationID: "8721147", onClose: {})
}
