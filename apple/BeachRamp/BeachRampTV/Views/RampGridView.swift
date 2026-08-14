import SwiftUI
import BeachStatus

/// The ramp status grid.
struct RampGridView: View {
    let ramps: [Ramp]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ramps) { ramp in
                    TVRampTile(ramp: ramp)
                }
            }
        }
    }
}

/// Compact ramp tile for the TV grid — card with indicator + name on top, status below.
struct TVRampTile: View {
    let ramp: Ramp

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: indicator + name
            HStack(spacing: 8) {
                Image(systemName: ramp.category.tvIcon)
                    .font(.system(size: 30))
                    .foregroundStyle(ramp.category.tvColor)

                Text(ramp.rampName.titleCased)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            // Status text — full width
            Text(ramp.accessStatus.titleCased)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(ramp.category.tvColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard()
    }
}
