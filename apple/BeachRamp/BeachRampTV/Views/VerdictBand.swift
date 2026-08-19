import SwiftUI
import BeachStatus

/// Which detail overlay is open. `.none` means the board is showing.
enum DetailPanel {
    case none, outlook, weather
}

/// One labeled micro-column inside a tile ("SAT / Good", "WATER / 70°") —
/// the label is what keeps similar numbers from needing decoding.
struct StatTileColumn {
    let label: String
    let value: String
    /// Verdict accent, rendered as a small solid square beside the value —
    /// the ramp-tile grammar. Color arrives as a block, never as thin
    /// colored text, which washes out against the bright midday skies.
    var color: Color? = nil
}

/// One stat tile's display strings: a kicker, labeled columns, and a detail
/// line (the surf read on Outlook, the tide state on Weather).
struct StatTileModel {
    let label: String
    let columns: [StatTileColumn]
    let detail: String
    /// Micro-label naming the detail line ("SURF") when the line's subject
    /// isn't in its own words; nil when it is ("Tide rising · …").
    var detailLabel: String? = nil
    let panel: DetailPanel
}

/// The verdict band: headline + subline on the left, two focusable
/// rectangular tiles (outlook / weather) on the right. The 22×76 accent bar
/// is what makes the headline readable at distance before the words resolve.
struct VerdictBand: View {
    let verdict: Verdict
    let stats: [StatTileModel]
    /// Owned by ContentView so it can restore focus to the tile that opened
    /// a detail overlay after that overlay closes.
    @FocusState.Binding var focusedStat: DetailPanel?
    let onSelect: (DetailPanel) -> Void

    @Environment(\.skyPalette) private var sky

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            headline
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 20) {
                ForEach(stats, id: \.label) { stat in
                    StatTile(stat: stat, focusedStat: $focusedStat, onSelect: onSelect)
                        .frame(width: 390)
                }
            }
            // Two 390pt rectangles. The group width holds when the outlook
            // tile is absent (old server, kill switch) so the weather tile
            // stays put on the right edge instead of ballooning.
            .frame(width: 800, alignment: .trailing)
        }
        // Focus section across the whole band (headline included) so Down
        // from the far-left city chip enters the stat tiles instead of
        // falling through to the rail — the tiles sit on the right edge.
        .focusSection()
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 20) {
                Rectangle()
                    .fill(sky.statusColor(for: verdict.category))
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
    @FocusState.Binding var focusedStat: DetailPanel?
    let onSelect: (DetailPanel) -> Void

    private var focused: Bool { focusedStat == stat.panel }

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
                HStack(spacing: 20) {
                    ForEach(stat.columns, id: \.label) { column in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(column.label)
                                .font(.system(size: 15, weight: .semibold))
                                .tracking(15 * 0.08)
                                .foregroundStyle(.white.opacity(0.55))
                            HStack(spacing: 8) {
                                if let color = column.color {
                                    Rectangle()
                                        .fill(color)
                                        .frame(width: 12, height: 24)
                                }
                                Text(column.value)
                                    .font(.system(size: 32, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let detailLabel = stat.detailLabel {
                        Text(detailLabel)
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(15 * 0.08)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Text(stat.detail)
                        .font(.system(size: 24))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(FlatFocusButtonStyle(
            isFocused: focused,
            cornerRadius: 0,
            horizontalPadding: 16,
            verticalPadding: 12
        ))
        .focused($focusedStat, equals: stat.panel)
    }
}

#Preview {
    @Previewable @FocusState var focusedStat: DetailPanel?
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
                    StatTileModel(label: "Outlook",
                                  columns: [StatTileColumn(label: "SAT", value: "Good", color: .green),
                                            StatTileColumn(label: "SUN", value: "Mixed", color: .orange)],
                                  detail: "Clean chest-high — worth a paddle",
                                  detailLabel: "SURF", panel: .outlook),
                    StatTileModel(label: "Weather",
                                  columns: [StatTileColumn(label: "WATER", value: "82°"),
                                            StatTileColumn(label: "AIR", value: "89°"),
                                            StatTileColumn(label: "WIND", value: "ENE 9")],
                                  detail: "Tide dropping · low 4:57 PM", panel: .weather),
                ],
                focusedStat: $focusedStat,
                onSelect: { _ in }
            )
            .padding(.horizontal, 60)
            .padding(.top, 56)
            Spacer()
        }
    }
}

#Preview("Closed") {
    @Previewable @FocusState var focusedStat: DetailPanel?
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
                    StatTileModel(label: "Outlook",
                                  columns: [StatTileColumn(label: "SAT", value: "Mixed", color: .orange),
                                            StatTileColumn(label: "SUN", value: "Tough", color: .red)],
                                  detail: "Blown out — choppy and messy",
                                  detailLabel: "SURF", panel: .outlook),
                    StatTileModel(label: "Weather",
                                  columns: [StatTileColumn(label: "WATER", value: "82°"),
                                            StatTileColumn(label: "AIR", value: "89°"),
                                            StatTileColumn(label: "WIND", value: "ENE 9")],
                                  detail: "Tide dropping · low 4:57 PM", panel: .weather),
                ],
                focusedStat: $focusedStat,
                onSelect: { _ in }
            )
            .padding(.horizontal, 60)
            .padding(.top, 56)
            Spacer()
        }
    }
}
