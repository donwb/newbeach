import SwiftUI
import BeachStatus

/// The sheet's 3-up stat strip: Tide / Water · Air / Wind, divided by 1px
/// rules, bounded by 2px rules above and below.
struct StatStripView: View {
    let tideInfo: TideInfo?
    let tideChart: TideChartData?
    let weather: WeatherInfo?
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        VStack(spacing: 0) {
            Rectangle().fill(t.rule).frame(height: 2)
            HStack(alignment: .top, spacing: 0) {
                cell(label: "Tide", value: tideValue, detail: tideDetail)
                Rectangle().fill(t.rule2).frame(width: 1)
                cell(label: "Water · Air", value: tempsValue, detail: tempsDetail)
                Rectangle().fill(t.rule2).frame(width: 1)
                cell(label: "Wind", value: windValue, detail: windDetail)
            }
            .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(t.rule).frame(height: 2)
        }
    }

    private func cell(label: String, value: String, detail: String?) -> some View {
        let t = ground.tokens
        return VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)
            Text(value)
                .font(.archivo(18, weight: .extraBold))
                .monospacedDigit()
                .foregroundStyle(t.ink)
            if let detail {
                Text(detail)
                    .font(.archivo(11))
                    .foregroundStyle(t.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Values

    /// Current tide height off the hourly curve, nearest to now.
    private var tideValue: String {
        guard let point = currentTidePoint else { return "—" }
        return String(format: "%.1f ft", point.height)
    }

    private var tideDetail: String? {
        guard let tideInfo else { return nil }
        return tideInfo.isRising ? "Rising" : "Falling"
    }

    private var currentTidePoint: HourlyTidePoint? {
        guard let chart = tideChart, !chart.hourly.isEmpty else { return nil }
        let now = Date()
        return chart.hourly.min {
            abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now))
        }
    }

    private var tempsValue: String {
        let water = tideInfo?.waterTempAvg.map { "\(Int($0.rounded()))°" } ?? "—"
        let air = weather?.current.temperatureF.map { "\(Int($0.rounded()))°" } ?? "—"
        return "\(water) · \(air)"
    }

    private var tempsDetail: String? {
        weather?.current.description
    }

    private var windValue: String {
        guard let current = weather?.current else { return "—" }
        let speed = current.windSpeed?.replacingOccurrences(of: " mph", with: "") ?? "—"
        return "\(speed) mph"
    }

    private var windDetail: String? {
        weather?.current.windDirection.map(expandDirection)
    }

    private func expandDirection(_ dir: String) -> String {
        let names: [String: String] = [
            "N": "North", "S": "South", "E": "East", "W": "West",
            "NE": "Northeast", "NW": "Northwest", "SE": "Southeast", "SW": "Southwest",
        ]
        return names[dir.uppercased()] ?? dir
    }
}
