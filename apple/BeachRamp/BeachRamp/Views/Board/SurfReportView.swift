import SwiftUI
import BeachStatus

/// The surf read: the server's casual line verbatim with the buoy facts
/// under it. An adjective on the board, not a feature — one block, no page.
/// Renders nothing when the server has no line (silent buoy, kill switch).
struct SurfReportView: View {
    let line: String?
    let detail: String?
    @Environment(\.ground) private var ground

    var body: some View {
        if let line, !line.isEmpty {
            let t = ground.tokens
            VStack(alignment: .leading, spacing: 6) {
                Text("Surf".uppercased())
                    .font(.archivo(10, weight: .bold))
                    .tracking(10 * ArchivoTracking.kicker)
                    .foregroundStyle(t.ink2)
                Text(line)
                    .font(.archivo(17, weight: .extraBold))
                    .tracking(17 * ArchivoTracking.rampName)
                    .foregroundStyle(t.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.archivo(11))
                        .monospacedDigit()
                        .foregroundStyle(t.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#if DEBUG
#Preview("Surf") {
    SurfReportView(line: "Clean chest-high — worth a paddle",
                   detail: "Chest-high · 9s · rip risk moderate · buoy read 40 min ago")
        .padding(18)
        .environment(\.ground, GroundModel(overrideDate: Calendar.current.startOfDay(for: Date()).addingTimeInterval(13 * 3600)).state)
}
#endif
