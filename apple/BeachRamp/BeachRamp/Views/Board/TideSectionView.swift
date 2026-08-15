import SwiftUI
import BeachStatus

/// The board's tide section: kicker, a 12-hour curve at 92pt with the ground
/// tidefill under the stroke and an accent now-line, extremes labelled below.
struct TideSectionView: View {
    let tideInfo: TideInfo?
    let tideChart: TideChartData?
    /// Chart height: 92 on the iPhone board, 104 on the iPad rail.
    var height: CGFloat = 92
    var windowHours: Double = 12
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        VStack(alignment: .leading, spacing: 10) {
            Text("Tide · Next \(Int(windowHours)) hours".uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)

            if points.count >= 2 {
                TideCurveShapeView(points: points, range: window, height: height)
                extremesRow
            } else {
                Text("Tide data unavailable")
                    .font(.archivo(13))
                    .foregroundStyle(t.ink2)
                    .frame(height: height)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Data

    private var window: ClosedRange<Date> {
        let now = Date()
        // Start an hour back so "now" doesn't sit on the left edge.
        return now.addingTimeInterval(-3600)...now.addingTimeInterval((windowHours - 1) * 3600)
    }

    private var points: [TideCurve.Point] {
        guard let chart = tideChart else { return [] }
        // Prefer the smooth curve from extremes; fall back to raw hourly.
        let fromExtremes = TideCurve.points(extremes: chart.highLow, in: window)
        if fromExtremes.count >= 2 { return fromExtremes }
        return chart.hourly
            .filter { window.contains($0.time) }
            .map { TideCurve.Point(time: $0.time, height: $0.height) }
    }

    /// The extremes inside the window, capped at one low + one high.
    private var windowExtremes: [TidePrediction] {
        guard let chart = tideChart else { return [] }
        let now = Date()
        return chart.highLow
            .filter { $0.time > now && window.contains($0.time) }
            .sorted { $0.time < $1.time }
            .prefix(2)
            .map { $0 }
    }

    private var extremesRow: some View {
        let t = ground.tokens
        return HStack {
            ForEach(Array(windowExtremes.enumerated()), id: \.element.id) { index, extreme in
                if index > 0 { Spacer() }
                VStack(alignment: index == 0 ? .leading : .trailing, spacing: 2) {
                    Text(extreme.label.uppercased())
                        .font(.archivo(10, weight: .bold))
                        .tracking(10 * ArchivoTracking.kicker)
                        .foregroundStyle(t.ink2)
                    Text("\(SinceFormatter.clock(extreme.time)) · \(extreme.heightDisplay ?? "—")")
                        .font(.archivo(15, weight: .extraBold))
                        .monospacedDigit()
                        .foregroundStyle(t.ink)
                }
            }
        }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let tideInfo {
            parts.append("Tide \(tideInfo.isRising ? "rising" : "falling")")
        }
        for extreme in windowExtremes {
            parts.append("\(extreme.label) \(SinceFormatter.clock(extreme.time))")
        }
        return parts.joined(separator: ", ")
    }
}
