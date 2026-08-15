import SwiftUI
import BeachStatus

/// The verdict: a solid bar in the verdict color, the headline, and the
/// subline aligned to the headline's text edge (not the bar's).
struct VerdictView: View {
    let verdict: Verdict
    @Environment(\.ground) private var ground

    /// iPad landscape uses 52/800; portrait 42; iPhone 40.
    var headlineSize: CGFloat = 40
    var sublineSize: CGFloat = 15

    /// The verdict color on the raw sky: the night-track status hues, which
    /// hold contrast over the gradient at every phase.
    private var barColor: Color {
        switch verdict.category {
        case .open: Color(red: 0x2A / 255, green: 0xE0 / 255, blue: 0x7A / 255)
        case .limited: Color(red: 0xF5 / 255, green: 0xA2 / 255, blue: 0x14 / 255)
        case .closed: Color(red: 0xE6 / 255, green: 0x3A / 255, blue: 0x2B / 255)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Rectangle()
                    .fill(barColor)
                    .frame(width: 12, height: 52)
                Text(verdict.headline)
                    .font(.archivo(headlineSize, weight: .extraBold))
                    .tracking(headlineSize * ArchivoTracking.headline)
                    .lineSpacing(-headlineSize * 0.16)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !verdict.subline.isEmpty {
                Text(verdict.subline)
                    .font(.archivo(sublineSize))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineSpacing(3)
                    .padding(.leading, 26)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
