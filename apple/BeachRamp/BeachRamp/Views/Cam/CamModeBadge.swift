import SwiftUI
import BeachStatus

/// LIVE / STILL / OFFLINE, in kicker type, next to every iOS cam picture so
/// a viewer always knows whether they're watching motion or a photo that
/// refreshes every few minutes. LIVE keeps the red dot the landscape cam has
/// always carried; STILL gets a hollow ring; OFFLINE a slashed camera.
struct CamModeBadge: View {
    let mode: CamMode
    /// Text color — `.white.opacity(0.85)` on the landscape scrim, the
    /// ground's `ink2` on the board.
    var tint: Color

    static let liveRed = Color(red: 0xE6 / 255, green: 0x3A / 255, blue: 0x2B / 255)

    var body: some View {
        HStack(spacing: 6) {
            switch mode {
            case .live:
                Circle().fill(Self.liveRed).frame(width: 8, height: 8)
            case .still:
                Circle().strokeBorder(tint, lineWidth: 1.5).frame(width: 8, height: 8)
            case .offline:
                Image(systemName: "video.slash")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        switch mode {
        case .live: "LIVE"
        case .still: "STILL"
        case .offline: "OFFLINE"
        }
    }

    private var accessibilityLabel: String {
        switch mode {
        case .live: "Live video"
        case .still: "Still photo, refreshed every few minutes"
        case .offline: "Cam offline"
        }
    }
}

#if DEBUG
#Preview("Badges") {
    VStack(alignment: .leading, spacing: 12) {
        CamModeBadge(mode: .live, tint: .primary)
        CamModeBadge(mode: .still, tint: .primary)
        CamModeBadge(mode: .offline, tint: .primary)
        HStack(spacing: 16) {
            CamModeBadge(mode: .live, tint: .white.opacity(0.85))
            CamModeBadge(mode: .still, tint: .white.opacity(0.85))
        }
        .padding(10)
        .background(.black)
    }
    .padding()
}
#endif
