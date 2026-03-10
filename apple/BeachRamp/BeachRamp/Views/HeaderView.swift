import SwiftUI
import BeachStatus

/// Top header bar with ocean gradient, weather summary, and tide info.
struct HeaderView: View {
    let viewModel: BeachViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Gradient header
            VStack(spacing: 12) {
                // Title row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Beach Ramp Status")
                            .font(.title2.weight(.bold))
                        Text("Volusia County, FL")
                            .font(.subheadline)
                            .opacity(0.8)
                    }
                    Spacer()

                    // Water temp pill
                    if let temp = viewModel.waterTempDisplay {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                                .font(.caption)
                            Text(temp)
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }

                // Info pills row
                HStack(spacing: 8) {
                    // Weather pill
                    if let current = viewModel.weather?.current {
                        InfoPill(
                            icon: "cloud.sun.fill",
                            text: current.tempDisplay,
                            detail: current.description
                        )
                    }

                    // Wind pill
                    if let current = viewModel.weather?.current, current.windSpeed != nil {
                        InfoPill(
                            icon: "wind",
                            text: current.windDisplay,
                            detail: current.gustDisplay
                        )
                    }

                    // Tide pill
                    if let tide = viewModel.tideInfo {
                        InfoPill(
                            icon: tide.isRising ? "arrow.up.right" : "arrow.down.right",
                            text: "\(tide.tidePercentage)%",
                            detail: tide.tideDirection
                        )
                    }

                    Spacer()
                }
            }
            .padding()
            .foregroundStyle(.white)
            .background(AppColors.headerGradient)
        }
    }
}

/// Small info pill used in the header.
struct InfoPill: View {
    let icon: String
    let text: String
    let detail: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .opacity(0.8)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.15))
        .clipShape(Capsule())
    }
}
