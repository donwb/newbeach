import SwiftUI

// MARK: - Board Surface Tokens
// From the 2026 redesign handoff. Radius is zero everywhere; structure is
// carried by 2pt borders and rules, not rounding or materials.

enum BoardColor {
    /// Deep translucent ink behind open ramp tiles — white type clears ~7:1
    /// against the noon sky through it.
    static let tileFieldOpen = Color(boardHex: 0x041822).opacity(0.55)
    static let tileBorderOpen = Color.white.opacity(0.30)

    static let chipFill = Color.white.opacity(0.06)
    static let chipBorder = Color.white.opacity(0.22)
    static let focusedFill = Color.white.opacity(0.26)
    static let focusedBorder = Color.white

    /// Opaque field behind every overlay and the cam-offline state.
    static let overlayField = Color(boardHex: 0x0A1420)
    /// rgba(6,18,28,0.62) — the cam banner's corner status chip.
    static let camChipFill = Color(boardHex: 0x06121C).opacity(0.62)

    static let ruleStrong = Color.white.opacity(0.40)
    static let ruleLight = Color.white.opacity(0.22)

    static let nowMarker = Color(boardHex: 0xFF4438)

    /// Text/mark color on the solid amber limited field.
    static let limitedInk = Color(boardHex: 0x241500)
}

extension Color {
    init(boardHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Kicker Text

extension Text {
    /// Small uppercase label: 22pt semibold, 0.08em tracking.
    func kickerStyle(opacity: Double = 0.65) -> some View {
        self.font(.system(size: 22, weight: .semibold))
            .tracking(22 * 0.08)
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(opacity))
    }
}

// MARK: - Flat Focus Button Style

/// A tvOS button style that fully replaces the system's frost-and-lift focus
/// treatment with a flat chip: a translucent fill and a 2pt border that
/// brighten on focus, plus a tiny press dip. No scaling on focus, so focused
/// chips stay put instead of ballooning over their neighbors. Zero radius.
struct FlatFocusButtonStyle: ButtonStyle {
    var isFocused: Bool
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 0
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 10
    /// Idle (unfocused) surface. The default matches the stat tiles; the city
    /// chip passes slightly stronger values per the spec.
    var idleFill: Double = 0.06
    var idleBorder: Double = 0.22

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(isFocused ? 0.26 : (isSelected ? 0.14 : idleFill)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        .white.opacity(isFocused ? 1.0 : (isSelected ? 0.6 : idleBorder)),
                        lineWidth: 2
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
