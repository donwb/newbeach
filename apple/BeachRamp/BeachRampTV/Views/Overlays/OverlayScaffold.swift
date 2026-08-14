import SwiftUI

/// Shared frame for the four full-screen overlays: an opaque flat field (not
/// a scrim — at any usable alpha the board's type collides with the panel's),
/// vertically centered content at width 1560, structured kicker → title row →
/// rule → body → footnote. Menu closes.
struct OverlayScaffold<Content: View>: View {
    let kicker: String
    let title: String
    var titleSize: CGFloat = 72
    var rightLine: String? = nil
    let footnote: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            BoardColor.overlayField
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text(kicker)
                    .kickerStyle()

                HStack(alignment: .lastTextBaseline) {
                    Text(title)
                        .font(.system(size: titleSize, weight: .bold))
                        .tracking(titleSize * -0.02)
                        .foregroundStyle(.white)
                    Spacer()
                    if let rightLine {
                        Text(rightLine)
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.top, 10)

                Rectangle()
                    .fill(BoardColor.ruleStrong)
                    .frame(height: 2)
                    .padding(.top, 24)

                content()

                Text(footnote)
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 26)
            }
            .frame(width: 1560, alignment: .leading)
            .padding(.horizontal, 120)
        }
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
        .onExitCommand { onClose() }
    }
}
