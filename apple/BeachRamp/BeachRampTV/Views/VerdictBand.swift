import SwiftUI
import BeachStatus

/// Which detail overlay is open. `.none` means the board is showing.
enum DetailPanel {
    case none, tide, temp, wind
}

/// One stat tile's display strings.
struct StatTileModel {
    let label: String
    let value: String
    let detail: String
    let panel: DetailPanel
}

/// The verdict band: headline + subline on the left, three focusable stat
/// tiles (tide / water & air / wind) on the right. The 22×76 accent bar is
/// what makes the headline readable at distance before the words resolve.
struct VerdictBand: View {
    let verdict: Verdict
    let stats: [StatTileModel]
    let onSelect: (DetailPanel) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            headline
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 20) {
                ForEach(stats, id: \.label) { stat in
                    StatTile(stat: stat, onSelect: onSelect)
                }
            }
            .frame(width: 687)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 20) {
                Rectangle()
                    .fill(verdict.category.statusColor)
                    .frame(width: 22, height: 76)
                Text(verdict.headline)
                    .font(.system(size: 84, weight: .bold))
                    .tracking(84 * -0.02)
                    .lineSpacing(84 * -0.08)
                    .lineLimit(2)
                    .foregroundStyle(.white)
            }
            if !verdict.subline.isEmpty {
                Text(verdict.subline)
                    .font(.system(size: 34, weight: .regular))
                    .lineSpacing(34 * 0.25)
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.leading, 42)
            }
        }
    }
}

/// A focusable stat tile. Select opens its detail panel.
private struct StatTile: View {
    let stat: StatTileModel
    let onSelect: (DetailPanel) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        Button {
            onSelect(stat.panel)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(stat.label)
                        .kickerStyle(opacity: 0.7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(stat.value)
                    .font(.system(size: 40, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.white)
                Text(stat.detail)
                    .font(.system(size: 24))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(FlatFocusButtonStyle(
            isFocused: focused,
            cornerRadius: 0,
            horizontalPadding: 16,
            verticalPadding: 12
        ))
        .focused($focused)
    }
}

#Preview {
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        VStack {
            VerdictBand(
                verdict: Verdict(
                    category: .open,
                    headline: "All five open",
                    subline: "Tide dropping · low 4:57 PM · 5h 41m of light left"
                ),
                stats: [
                    StatTileModel(label: "Tide", value: "Dropping", detail: "Low 4:57 PM", panel: .tide),
                    StatTileModel(label: "Water · Air", value: "82° · 89°", detail: "Mostly clear", panel: .temp),
                    StatTileModel(label: "Wind", value: "ENE 9", detail: "Sat 93°", panel: .wind),
                ],
                onSelect: { _ in }
            )
            .padding(.horizontal, 60)
            .padding(.top, 56)
            Spacer()
        }
    }
}

#Preview("Closed") {
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        VStack {
            VerdictBand(
                verdict: Verdict(
                    category: .closed,
                    headline: "Crawford Rd closed",
                    subline: "Four open · closed for high tide since 12:48 PM · reopens near 6:30 PM"
                ),
                stats: [
                    StatTileModel(label: "Tide", value: "Dropping", detail: "Low 4:57 PM", panel: .tide),
                    StatTileModel(label: "Water · Air", value: "82° · 89°", detail: "Mostly clear", panel: .temp),
                    StatTileModel(label: "Wind", value: "ENE 9", detail: "Sat 93°", panel: .wind),
                ],
                onSelect: { _ in }
            )
            .padding(.horizontal, 60)
            .padding(.top, 56)
            Spacer()
        }
    }
}
