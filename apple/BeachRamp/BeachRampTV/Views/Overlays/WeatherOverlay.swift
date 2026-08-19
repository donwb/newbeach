import SwiftUI
import Charts
import BeachStatus

/// Full-screen combined weather detail — everything the old tide,
/// water & air, and wind overlays showed, on one screen: the day's tide
/// curve and extremes, water temperature by station, and the NWS forecast
/// periods with temperature, wind, and conditions.
struct WeatherOverlay: View {
    let tide: TideInfo?
    let weather: WeatherInfo?
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
            kicker: "Weather",
            title: title,
            rightLine: weather?.current.description,
            footnote: "NOAA station \(stationID) tides & water temps · NWS api.weather.gov · press Menu to close",
            onClose: onClose
        ) {
            chart
                .frame(height: 150)
                .padding(.top, 24)

            extremesRow
                .padding(.top, 20)

            Rectangle()
                .fill(BoardColor.ruleStrong)
                .frame(height: 2)
                .padding(.top, 24)

            stationsRow
                .padding(.top, 20)

            Rectangle()
                .fill(BoardColor.ruleStrong)
                .frame(height: 2)
                .padding(.top, 24)

            forecastRow
                .padding(.top, 20)
        }
    }

    /// "Water 83° · Air 84° · Wind ENE 9" — the board's three spot values.
    private var title: String {
        var parts: [String] = []
        if let water = tide?.waterTempAvg {
            parts.append("Water \(Int(water))°")
        }
        if let air = weather?.current.temperatureF {
            parts.append("Air \(Int(air))°")
        }
        if let current = weather?.current {
            let direction = current.windDirection ?? ""
            let speed = current.windSpeed?.split(separator: " ").first.map(String.init) ?? ""
            let joined = "\(direction) \(speed)".trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { parts.append("Wind \(joined)") }
        }
        return parts.isEmpty ? "Weather" : parts.joined(separator: " · ")
    }

    // MARK: Tide

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

    private var extremesRow: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(todaysExtremes, id: \.time) { extreme in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tideKicker(extreme))
                        .kickerStyle()
                    Text(SinceFormatter.clock(extreme.time))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                    Text(extreme.heightDisplay ?? " ")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// "Low"/"High", marked "next" for the first extreme still coming.
    private func tideKicker(_ extreme: TidePrediction) -> String {
        guard let tide, let next = VerdictBuilder.nextExtreme(in: tide, after: now),
              next.time == extreme.time else { return extreme.label }
        return "Next \(extreme.label.lowercased())"
    }

    private var todaysExtremes: [TidePrediction] {
        (tide?.predictions ?? []).filter {
            eastern.isDate($0.time, inSameDayAs: now)
        }
    }

    // MARK: Water stations

    private struct Station {
        let kicker: String
        let value: String
        let source: String
    }

    private var stations: [Station] {
        var out: [Station] = (tide?.waterTemps ?? []).map { reading in
            let parts = reading.stationName.split(separator: ",", maxSplits: 1)
            let name = parts.first.map(String.init) ?? reading.stationName
            let place = parts.count > 1
                ? parts[1].trimmingCharacters(in: .whitespaces)
                : ""
            let source = place.isEmpty
                ? "Station \(reading.stationID)"
                : "Station \(reading.stationID) · \(place)"
            return Station(kicker: name, value: "\(Int(reading.tempF))°", source: source)
        }
        if let avg = tide?.waterTempAvg {
            out.append(Station(kicker: "Average", value: "\(Int(avg))°",
                               source: "What the board shows"))
        }
        return out
    }

    private var stationsRow: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(stations, id: \.kicker) { station in
                VStack(alignment: .leading, spacing: 6) {
                    Text(station.kicker)
                        .kickerStyle()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(station.value)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                    Text(station.source)
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Forecast

    private var forecastRow: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach((weather?.forecast ?? []).prefix(6)) { period in
                VStack(alignment: .leading, spacing: 6) {
                    Text(period.name)
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(period.temperature)°")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                    Text(windLine(period))
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    Text(period.shortDescription)
                        .font(.system(size: 22))
                        .lineSpacing(22 * 0.3)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// "SSE 5–10" — direction plus the compacted speed range.
    private func windLine(_ period: ForecastPeriod) -> String {
        let speed = period.windSpeed
            .replacingOccurrences(of: " to ", with: "–")
            .replacingOccurrences(of: " mph", with: "")
        return "\(period.windDirection) \(speed)".trimmingCharacters(in: .whitespaces)
    }
}

#if DEBUG
#Preview {
    WeatherOverlay(tide: PreviewFixtures.tide, weather: PreviewFixtures.weather,
                   stationID: "8721147", onClose: {})
}
#endif
