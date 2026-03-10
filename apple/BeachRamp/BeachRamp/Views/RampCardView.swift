import SwiftUI
import BeachStatus

/// Card showing a single ramp's name, location, and status.
struct RampCardView: View {
    let ramp: Ramp

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: ramp.category.iconName)
                .font(.title2)
                .foregroundStyle(ramp.category.color)
                .frame(width: 32)

            // Ramp info
            VStack(alignment: .leading, spacing: 4) {
                Text(ramp.rampName.titleCased)
                    .font(.headline)
                    .foregroundStyle(AppColors.primaryText)

                Text(ramp.locationDisplay)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Status badge
            StatusBadge(category: ramp.category, text: ramp.accessStatus.titleCased)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.cardBackground)
        }
    }
}

/// Small colored badge showing status text.
struct StatusBadge: View {
    let category: StatusCategory
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(category.color)
            .background {
                Capsule()
                    .fill(category.color.opacity(0.15))
            }
    }
}

#Preview {
    VStack(spacing: 12) {
        RampCardView(ramp: .preview(status: "open"))
        RampCardView(ramp: .preview(status: "limited"))
        RampCardView(ramp: .preview(status: "closed"))
    }
    .padding()
}

// MARK: - Preview Helpers

extension Ramp {
    static func preview(status: String) -> Ramp {
        Ramp(
            id: 1,
            rampName: "SMYRNA DUNES PARK",
            accessStatus: status == "open" ? "OPEN" : status == "limited" ? "LIMITED ACCESS" : "CLOSED",
            statusCategory: status,
            objectID: 100,
            city: "NEW SMYRNA BEACH",
            accessID: "NSB-001",
            location: "PENINSULA AVE",
            lastUpdated: Date()
        )
    }
}
