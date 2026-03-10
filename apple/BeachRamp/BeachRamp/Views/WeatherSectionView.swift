import SwiftUI
import BeachStatus

/// Weather forecast section with horizontally scrolling cards.
struct WeatherSectionView: View {
    let weather: WeatherInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Label("Weather Forecast", systemImage: "cloud.sun.fill")
                .font(.headline)

            if let weather, !weather.forecast.isEmpty {
                // Show only daytime periods for the cards
                let daytimePeriods = weather.forecast.filter(\.isDaytime)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(daytimePeriods) { period in
                            WeatherCard(period: period)
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Forecast", systemImage: "cloud.slash")
                } description: {
                    Text("Weather forecast is currently unavailable.")
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.cardBackground)
        }
    }
}

/// Individual weather forecast card.
struct WeatherCard: View {
    let period: ForecastPeriod

    var body: some View {
        VStack(spacing: 8) {
            // Day label
            Text(period.shortName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)

            // Weather icon
            weatherIcon
                .font(.title2)
                .foregroundStyle(iconColor)

            // Temperature
            Text(period.tempDisplay)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.primaryText)

            // Short description
            Text(period.shortDescription)
                .font(.caption2)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 80)

            // Wind
            HStack(spacing: 2) {
                Image(systemName: "wind")
                    .font(.caption2)
                Text(period.windSpeed)
                    .font(.caption2)
            }
            .foregroundStyle(AppColors.secondaryText)

            // Gusts (if any)
            if let gust = period.windGust, !gust.isEmpty {
                Text("Gusts \(gust)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(width: 100)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        }
    }

    private var weatherIcon: Image {
        let desc = period.shortDescription.lowercased()
        if desc.contains("thunder") || desc.contains("storm") {
            return Image(systemName: "cloud.bolt.fill")
        } else if desc.contains("rain") || desc.contains("shower") {
            return Image(systemName: "cloud.rain.fill")
        } else if desc.contains("cloud") || desc.contains("overcast") {
            return Image(systemName: "cloud.fill")
        } else if desc.contains("partly") {
            return Image(systemName: "cloud.sun.fill")
        } else if desc.contains("fog") || desc.contains("haze") {
            return Image(systemName: "cloud.fog.fill")
        } else if desc.contains("snow") {
            return Image(systemName: "snowflake")
        } else {
            return Image(systemName: "sun.max.fill")
        }
    }

    private var iconColor: Color {
        let desc = period.shortDescription.lowercased()
        if desc.contains("thunder") || desc.contains("storm") {
            return .purple
        } else if desc.contains("rain") || desc.contains("shower") {
            return .blue
        } else if desc.contains("cloud") || desc.contains("overcast") || desc.contains("partly") {
            return .gray
        } else {
            return .orange
        }
    }
}
