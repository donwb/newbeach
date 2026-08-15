import SwiftUI

// Foreground tokens for the sun-following ground, from the iOS design
// handoff. Tokens flip as a set at dayness < 0.5 — never interpolate them,
// or text sits at an in-between contrast. (The ground underneath does
// interpolate; only the ink flips.)

extension Color {
    /// 0xRRGGBB + alpha. Internal — app targets have their own conveniences.
    init(token hex: Int, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// One complete foreground token set. `day` on the veiled cream ground,
/// `night` directly on the sky.
public struct TokenSet: Sendable {
    public let ink: Color
    /// Secondary text.
    public let ink2: Color
    /// Structural 2px rules.
    public let rule: Color
    /// Hairline 1px rules.
    public let rule2: Color
    public let accent: Color
    /// Fill under the tide curve stroke.
    public let tideFill: Color

    public static let day = TokenSet(
        ink: Color(token: 0x201E1D),
        ink2: Color(token: 0x201E1D, alpha: 0.62),
        rule: Color(token: 0x201E1D, alpha: 0.85),
        rule2: Color(token: 0x201E1D, alpha: 0.22),
        accent: Color(token: 0xEC3013),
        tideFill: Color(token: 0x201E1D, alpha: 0.10)
    )

    public static let night = TokenSet(
        ink: .white,
        ink2: Color(token: 0xFFFFFF, alpha: 0.72),
        rule: Color(token: 0xFFFFFF, alpha: 0.40),
        rule2: Color(token: 0xFFFFFF, alpha: 0.22),
        accent: Color(token: 0xFF6A4D),
        tideFill: Color(token: 0xFFFFFF, alpha: 0.14)
    )
}

/// Status carried by the card field itself, not a colored pill: open is a
/// bordered white card, limited and closed are solid fields. Red lightens at
/// night because #D22B18 on the night sky is under 3:1.
public struct StatusField: Sendable {
    public let fill: Color
    public let border: Color
    /// Text placed on the field.
    public let text: Color
    /// Secondary text on the field (since lines).
    public let text2: Color
    /// The solid status mark rectangle.
    public let mark: Color

    public static func field(for category: StatusCategory, isDay: Bool) -> StatusField {
        switch category {
        case .open:
            return StatusField(
                fill: isDay ? .white : Color(token: 0x041822, alpha: 0.55),
                border: isDay ? Color(token: 0x201E1D, alpha: 0.85) : Color(token: 0xFFFFFF, alpha: 0.30),
                text: isDay ? Color(token: 0x201E1D) : .white,
                text2: isDay ? Color(token: 0x201E1D, alpha: 0.62) : Color(token: 0xFFFFFF, alpha: 0.72),
                mark: isDay ? Color(token: 0x0A7A42) : Color(token: 0x2AE07A)
            )
        case .limited:
            let ink = Color(token: 0x241500)
            return StatusField(
                fill: Color(token: 0xF5A214),
                border: Color(token: 0xF5A214),
                text: ink,
                text2: ink.opacity(0.72),
                mark: ink
            )
        case .closed:
            return StatusField(
                fill: isDay ? Color(token: 0xD22B18) : Color(token: 0xE63A2B),
                border: isDay ? Color(token: 0xD22B18) : Color(token: 0xE63A2B),
                text: .white,
                text2: Color(token: 0xFFFFFF, alpha: 0.80),
                mark: .white
            )
        }
    }
}
