import SwiftUI
import BeachStatus

/// "Pin to widget": the only thing a pin does is put the ramp in the
/// widget's "Pinned ramps" view on this device. Labelled as such so nobody
/// expects it to filter the board or follow them to the web or the TV.
struct PinToWidgetButton: View {
    let isPinned: Bool
    let action: () -> Void
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .semibold))
                Text(isPinned ? "Pinned to widget" : "Pin to widget")
                    .font(.archivo(12, weight: .extraBold))
            }
            .foregroundStyle(isPinned ? t.accent : t.ink2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressTintButtonStyle())
        .accessibilityLabel(isPinned ? "Unpin from widget" : "Pin to widget")
    }
}
