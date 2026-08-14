#if canImport(SwiftUI)
import SwiftUI

/// Canonical status colors, shared by every platform. Retuned in the 2026
/// tvOS redesign to hold contrast against the sky gradient at both ends of
/// the day; replaces the per-target tvStatus*/statusOpen families.
public extension StatusCategory {
    /// open `#2AE07A` · limited `#F5A214` · closed `#E63A2B`
    var statusColor: Color {
        switch self {
        case .open: Color(statusHex: 0x2AE07A)
        case .limited: Color(statusHex: 0xF5A214)
        case .closed: Color(statusHex: 0xE63A2B)
        }
    }
}

extension Color {
    /// Internal so it can't collide with app-target `Color(hex:)` helpers.
    init(statusHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
#endif
