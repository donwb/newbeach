import SwiftUI
import BeachStatus

/// The row that opens the landscape cam view. A 1280×270 panorama does not
/// fit a portrait column — the cam lives in its own landscape screen. This
/// row should simply not appear when the camera roster is empty.
struct CamRowView: View {
    let cameraName: String
    let action: () -> Void
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live cam · \(cameraName)")
                        .font(.archivo(17, weight: .extraBold))
                        .foregroundStyle(t.ink)
                    Text("Turn the phone sideways to watch")
                        .font(.archivo(11))
                        .foregroundStyle(t.ink2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(t.accent)
            }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressTintButtonStyle())
        .accessibilityLabel("Live cam, \(cameraName). Opens full screen in landscape.")
    }
}

/// The board's footer: sources and the feed timestamp.
struct BoardFooterView: View {
    let updatedAt: Date?
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        VStack(alignment: .leading, spacing: 2) {
            Text("NOAA · Volusia County Beach Safety")
                .font(.archivo(11))
                .foregroundStyle(t.ink2)
            if let updatedAt {
                Text("Updated \(SinceFormatter.clock(updatedAt))")
                    .font(.archivo(11))
                    .monospacedDigit()
                    .foregroundStyle(t.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
