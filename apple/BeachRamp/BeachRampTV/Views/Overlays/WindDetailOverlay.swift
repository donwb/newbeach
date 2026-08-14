import SwiftUI
import BeachStatus

/// Full-screen wind detail: a direction axis (matching the board's
/// position-on-a-line vocabulary) and wind by forecast period.
struct WindDetailOverlay: View {
    let weather: WeatherInfo?
    let onClose: () -> Void

    /// Compass point → degrees, for the axis marker.
    private static let compassDegrees: [String: Double] = [
        "N": 0, "NNE": 22.5, "NE": 45, "ENE": 67.5,
        "E": 90, "ESE": 112.5, "SE": 135, "SSE": 157.5,
        "S": 180, "SSW": 202.5, "SW": 225, "WSW": 247.5,
        "W": 270, "WNW": 292.5, "NW": 315, "NNW": 337.5,
    ]

    var body: some View {
        OverlayScaffold(
            kicker: "Wind",
            title: title,
            rightLine: rightLine,
            footnote: "NWS api.weather.gov · mph · press Menu to close",
            onClose: onClose
        ) {
            directionAxis
                .padding(.top, 34)

            Rectangle()
                .fill(BoardColor.ruleStrong)
                .frame(height: 2)
                .padding(.top, 34)

            forecastRow
                .padding(.top, 24)
        }
    }

    private var current: CurrentConditions? { weather?.current }

    private var title: String {
        guard let current, let speed = current.windSpeed, speed != "0 mph" else { return "Calm" }
        let direction = current.windDirection ?? ""
        return "\(direction) \(speed)".trimmingCharacters(in: .whitespaces)
    }

    private var degrees: Double? {
        current?.windDirection.flatMap { Self.compassDegrees[$0] }
    }

    /// Onshore/offshore for a north–south Atlantic coastline: the east
    /// component of the wind vector decides.
    private var rightLine: String? {
        guard let degrees else { return nil }
        let east = sin(degrees * .pi / 180)
        let shore = east > 0.25 ? "Onshore" : (east < -0.25 ? "Offshore" : "Alongshore")
        return "\(shore) · \(Int(degrees))°"
    }

    // MARK: Direction axis

    private var directionAxis: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.10), .white.opacity(0.34), .white.opacity(0.10)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(height: 18)
                        .frame(maxHeight: .infinity, alignment: .center)

                    if let degrees {
                        Rectangle()
                            .fill(StatusCategory.limited.statusColor)
                            .frame(width: 4, height: 34)
                            .offset(x: geo.size.width * degrees / 360 - 2)
                    }
                }
            }
            .frame(height: 34)

            HStack {
                ForEach(Array(["N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"].enumerated()),
                        id: \.offset) { item in
                    if item.offset > 0 { Spacer() }
                    Text(item.element)
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.75))
                }
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
                    Text(speedRange(period.windSpeed))
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                    Text(period.windDirection)
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// "5 to 10 mph" → "5–10", "5 mph" → "5".
    private func speedRange(_ raw: String) -> String {
        raw.replacingOccurrences(of: " to ", with: "–")
            .replacingOccurrences(of: " mph", with: "")
    }
}

#if DEBUG
#Preview {
    WindDetailOverlay(weather: PreviewFixtures.weather, onClose: {})
}
#endif
