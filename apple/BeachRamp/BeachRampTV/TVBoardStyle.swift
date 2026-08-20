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

// MARK: - Display Modes

/// The two presentations of the board, one D-pad press apart (the modes
/// handoff): Cam mode rests on the picture at its largest sharp size; Board
/// mode settles the cam into a header band and fills in the full board.
/// Not a setting — a direction. Raw value is persisted across launches.
enum TVBoardMode: String {
    case cam, board
}

// MARK: - Design v3 Tokens
// From "tvOS design v3" (panorama header, inline selectors). The board's
// status palette is specified per-field in the handoff and carried here as
// TV-local tokens — the shared StatusColors stay untouched for iOS/web.

/// The four ramp-card states of design v3. `overnight` exists so an expected
/// end-of-driving close is not drawn in the same field as a storm or tide
/// closure — red is reserved for a closure nobody planned.
enum TVRampState {
    case open, limited, closed, overnight

    var field: Color {
        switch self {
        case .open: Color(boardHex: 0x041A28).opacity(0.42)
        case .limited: Color(boardHex: 0xF5A214)
        case .closed: Color(boardHex: 0xC9301C)
        case .overnight: Color(boardHex: 0x040814).opacity(0.42)
        }
    }

    var border: Color {
        switch self {
        case .open: .white.opacity(0.28)
        case .limited: Color(boardHex: 0xF5A214)
        case .closed: Color(boardHex: 0xC9301C)
        case .overnight: .white.opacity(0.20)
        }
    }

    var ink: Color {
        switch self {
        case .open, .closed: .white
        case .limited: Color(boardHex: 0x241500)
        case .overnight: .white.opacity(0.72)
        }
    }

    var mark: Color {
        switch self {
        case .open: BoardColor.verdictGood
        case .limited: Color(boardHex: 0x241500)
        case .closed: .white
        case .overnight: .white.opacity(0.45)
        }
    }
}

extension BoardColor {
    /// Verdict-mark palette shared by ramp cards, the verdict bar, and day
    /// panels: great/good green, mixed amber, rough coral, no-call muted.
    static let verdictGood = Color(boardHex: 0x2AE07A)
    static let verdictMixed = Color(boardHex: 0xF5A214)
    static let verdictRough = Color(boardHex: 0xFF5240)
    static let verdictMuted = Color.white.opacity(0.45)

    /// The band's amber accent: live-neighbor cam names, elevated rip risk,
    /// the "All 7 days" cta.
    static let amberAccent = Color(boardHex: 0xFFC48A)

    /// Mark color for a weekend verdict word. Unknown future server values
    /// fall through to muted — never colored.
    static func verdictMark(for verdict: String) -> Color {
        switch verdict {
        case "great", "good": verdictGood
        case "mixed": verdictMixed
        case "tough": verdictRough
        default: verdictMuted
        }
    }

    /// Translucent ink field behind the Ahead-band panels.
    static let aheadField = Color(boardHex: 0x041A28).opacity(0.42)
    static let dayPanelField = Color(boardHex: 0x041A28).opacity(0.52)
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
