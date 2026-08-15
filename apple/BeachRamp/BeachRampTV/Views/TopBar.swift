import SwiftUI
import BeachStatus

/// Data freshness as the header chip presents it.
enum Freshness: Equatable {
    case live
    case stale(minutes: Int)
}

/// Header: city selector (left), freshness chip + clock (right).
struct TopBar: View {
    let city: String
    let time: String
    let freshness: Freshness
    let onNextCity: () -> Void

    @FocusState private var cityFocused: Bool
    @Environment(\.skyPalette) private var sky

    var body: some View {
        HStack(alignment: .center) {
            Button {
                onNextCity()
            } label: {
                HStack(spacing: 14) {
                    Text(city)
                        .font(.system(size: 38, weight: .bold))
                        .tracking(38 * -0.01)
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.system(size: 22))
                        .opacity(0.6)
                }
            }
            .buttonStyle(FlatFocusButtonStyle(
                isFocused: cityFocused,
                cornerRadius: 0,
                horizontalPadding: 16,
                verticalPadding: 8,
                idleFill: 0.10,
                idleBorder: 0.28
            ))
            .focused($cityFocused)
            // Pull the chip back so its padding doesn't shift the title's left edge.
            .padding(.leading, -16)

            Spacer()

            HStack(spacing: 24) {
                freshnessChip
                Text(time)
                    .font(.system(size: 38, weight: .regular))
                    .monospacedDigit()
            }
        }
        .frame(height: 56)
        .foregroundStyle(.white)
        // Row-level focus section: the row's only control sits far left, so
        // without this, Up from the right-side stat tiles skips the row.
        .focusSection()
    }

    @ViewBuilder private var freshnessChip: some View {
        let isStale = freshness != .live
        HStack(spacing: 12) {
            Circle()
                .fill(sky.statusColor(for: isStale ? .limited : .open))
                .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 24, weight: .semibold))
                .tracking(24 * 0.04)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        // Rectangle, not a bare Color: ShapeStyle backgrounds default to
        // ignoresSafeAreaEdges: .all and smear to the screen edge up here.
        .background(Rectangle().fill(isStale
            ? sky.statusColor(for: .limited).opacity(0.22)
            : Color.white.opacity(0.10)))
        .overlay(
            Rectangle().strokeBorder(
                isStale ? sky.statusColor(for: .limited) : Color.white.opacity(0.28),
                lineWidth: 2
            )
        )
    }

    private var label: String {
        switch freshness {
        case .live: "Live"
        case .stale(let minutes): "Stale · \(minutes) min"
        }
    }
}

#Preview("Live") {
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        VStack {
            TopBar(city: "New Smyrna Beach", time: "1:30 PM", freshness: .live, onNextCity: {})
                .padding(.horizontal, 60)
                .padding(.top, 56)
            Spacer()
        }
    }
}

#Preview("Stale") {
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        VStack {
            TopBar(city: "New Smyrna Beach", time: "1:30 PM", freshness: .stale(minutes: 14), onNextCity: {})
                .padding(.horizontal, 60)
                .padding(.top, 56)
            Spacer()
        }
    }
}
