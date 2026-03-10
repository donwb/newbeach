import SwiftUI
import Charts
import BeachStatus

/// Tide height chart with hourly data, high/low markers, and "now" indicator.
struct TideChartView: View {
    let chartData: TideChartData?
    let tideInfo: TideInfo?

    @Environment(\.colorScheme) private var colorScheme

    private var lineColor: Color {
        colorScheme == .dark ? .ocean500 : .ocean600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Label("Tide Chart", systemImage: "water.waves")
                    .font(.headline)
                Spacer()
                if let tide = tideInfo {
                    HStack(spacing: 4) {
                        Image(systemName: tide.isRising ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(tide.isRising ? Color.statusOpen : Color.ocean500)
                        Text("\(tide.tideDirection) \(tide.tidePercentage)%")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }

            if let data = chartData, !data.hourly.isEmpty {
                Chart {
                    // Area fill
                    ForEach(data.hourly) { point in
                        AreaMark(
                            x: .value("Time", point.time),
                            y: .value("Height", point.height)
                        )
                        .foregroundStyle(lineColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    }

                    // Line
                    ForEach(data.hourly) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Height", point.height)
                        )
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    // High/Low markers
                    ForEach(data.highLow) { hl in
                        PointMark(
                            x: .value("Time", hl.time),
                            y: .value("Height", heightAt(time: hl.time, in: data.hourly))
                        )
                        .foregroundStyle(hl.type == "H" ? Color.tideHigh : Color.tideLow)
                        .symbolSize(60)
                        .annotation(position: hl.type == "H" ? .top : .bottom) {
                            Text(hl.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(hl.type == "H" ? Color.tideHigh : Color.tideLow)
                        }
                    }

                    // "Now" rule line
                    RuleMark(x: .value("Now", data.currentTime))
                        .foregroundStyle(Color.tideNow)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 200)

                // High/Low predictions below the chart
                if let predictions = tideInfo?.predictions, !predictions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(predictions) { pred in
                                VStack(spacing: 2) {
                                    Text(pred.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(pred.type == "H" ? Color.tideHigh : Color.tideLow)
                                    Text(pred.timeDisplay)
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.secondaryText)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(AppColors.cardBackground)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Tide Data", systemImage: "water.waves.slash")
                } description: {
                    Text("Tide chart data is currently unavailable.")
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.cardBackground)
        }
    }

    /// Find the height at a given time by interpolating the hourly points.
    private func heightAt(time: Date, in points: [HourlyTidePoint]) -> Double {
        // Find the closest point
        let sorted = points.sorted { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
        return sorted.first?.height ?? 0
    }
}
