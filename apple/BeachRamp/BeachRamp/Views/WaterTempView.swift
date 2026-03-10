import SwiftUI
import BeachStatus

/// Section showing water temperature readings from NOAA stations.
struct WaterTempView: View {
    let tideInfo: TideInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Water Temperature", systemImage: "thermometer.medium")
                .font(.headline)

            if let temps = tideInfo?.waterTemps, !temps.isEmpty {
                ForEach(temps) { reading in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reading.stationName)
                                .font(.subheadline.weight(.medium))
                            Text("Station \(reading.stationID)")
                                .font(.caption)
                                .foregroundStyle(AppColors.secondaryText)
                        }

                        Spacer()

                        Text("\(Int(reading.tempF))°F")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.ocean600)
                    }
                    .padding(.vertical, 4)
                }

                // Average
                if let avg = tideInfo?.waterTempAvg {
                    Divider()
                    HStack {
                        Text("Average")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(avg))°F")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.ocean700)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Data", systemImage: "thermometer.slash")
                } description: {
                    Text("Water temperature data is currently unavailable.")
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
