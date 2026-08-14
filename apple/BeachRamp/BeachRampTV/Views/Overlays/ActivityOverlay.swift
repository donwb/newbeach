import SwiftUI
import BeachStatus

/// Recent-changes overlay — the only place the activity feed appears on tvOS.
/// Opens from Menu; the board never shows it unprompted.
struct ActivityOverlay: View {
    let city: String
    let entries: [ActivityEntry]
    let onClose: () -> Void

    var body: some View {
        OverlayScaffold(
            kicker: "Recent changes · \(city)",
            title: "Today",
            titleSize: 56,
            footnote: "Press Menu to close · the board never shows this unprompted",
            onClose: onClose
        ) {
            if entries.isEmpty {
                Text("No status changes today")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 40)
            } else {
                rows
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                LazyVGrid(
                    columns: [
                        GridItem(.fixed(180), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                    ],
                    spacing: 32
                ) {
                    Text(SinceFormatter.string(from: entry.recordedAt))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                    Text(entry.rampDisplayName ?? entry.accessID)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(entry.statusDisplay)
                        .foregroundStyle(.white)
                }
                .font(.system(size: 30))
                .padding(.vertical, 22)

                Rectangle()
                    .fill(index == entries.count - 1 ? BoardColor.ruleStrong : BoardColor.ruleLight)
                    .frame(height: index == entries.count - 1 ? 2 : 1)
            }
        }
    }
}

#Preview {
    ActivityOverlay(city: "New Smyrna Beach", entries: PreviewFixtures.activity, onClose: {})
}

#Preview("Empty") {
    ActivityOverlay(city: "New Smyrna Beach", entries: [], onClose: {})
}
