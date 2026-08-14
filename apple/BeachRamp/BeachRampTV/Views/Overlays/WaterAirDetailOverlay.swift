import SwiftUI
import BeachStatus

/// Full-screen water & air detail: both NOAA stations plus the average the
/// board shows, then all six NWS forecast periods.
struct WaterAirDetailOverlay: View {
    let tide: TideInfo?
    let weather: WeatherInfo?
    let onClose: () -> Void

    var body: some View {
        OverlayScaffold(
            kicker: "Water & air",
            title: title,
            rightLine: weather?.current.description,
            footnote: "NOAA water temperature · NWS api.weather.gov · press Menu to close",
            onClose: onClose
        ) {
            stationsRow
                .padding(.top, 30)

            Rectangle()
                .fill(BoardColor.ruleStrong)
                .frame(height: 2)
                .padding(.top, 30)

            forecastRow
                .padding(.top, 24)
        }
    }

    private var title: String {
        let water = tide?.waterTempAvg.map { "\(Int($0))°" } ?? "—"
        let air = weather?.current.temperatureF.map { "\(Int($0))°" } ?? "—"
        return "Water \(water) · Air \(air)"
    }

    // MARK: Stations

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
                VStack(alignment: .leading, spacing: 8) {
                    Text(station.kicker)
                        .kickerStyle()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(station.value)
                        .font(.system(size: 52, weight: .bold))
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
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
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
}

#Preview {
    WaterAirDetailOverlay(tide: PreviewFixtures.tide, weather: PreviewFixtures.weather, onClose: {})
}
