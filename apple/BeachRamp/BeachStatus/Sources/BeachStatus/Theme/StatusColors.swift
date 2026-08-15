#if canImport(SwiftUI)
import SwiftUI

/// Canonical status colors, shared by every platform. Retuned in the 2026
/// tvOS redesign to hold contrast against the sky gradient, then again in
/// August 2026 into the coastal family the sky already uses — sea green,
/// sandy amber, terracotta — so closed fields stop reading as traffic-light
/// red against the night board.
public extension StatusCategory {
    /// open `#29C97A` · limited `#E8A23C` · closed `#C64B38`
    var statusColor: Color {
        Color(red: statusRGB.red, green: statusRGB.green, blue: statusRGB.blue)
    }

    /// Raw sRGB components of `statusColor`, for surfaces that interpolate
    /// status colors numerically (the tvOS board mutes them toward the
    /// night sky as the sun sets).
    var statusRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .open: Self.rgb(0x29C97A)
        case .limited: Self.rgb(0xE8A23C)
        case .closed: Self.rgb(0xC64B38)
        }
    }

    private static func rgb(_ hex: UInt32) -> (red: Double, green: Double, blue: Double) {
        (
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
#endif
