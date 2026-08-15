import SwiftUI
import BeachStatus

// MARK: - TV Color Palette (large screen optimized)

extension Color {
    static let tvOcean500 = Color(red: 0.08, green: 0.72, blue: 0.65)
    static let tvOcean600 = Color(red: 0.05, green: 0.58, blue: 0.53)
    static let tvOcean700 = Color(red: 0.06, green: 0.46, blue: 0.43)
    static let tvOcean800 = Color(red: 0.07, green: 0.37, blue: 0.35)

    static let tvSand50 = Color(red: 1.0, green: 0.99, blue: 0.95)
}

// MARK: - Time-of-Day Sky

// SkyPalette (the sixteen sun phases) and the \.skyPalette environment key
// moved to the shared BeachStatus package so iOS, widgets, and the Watch
// inherit the same sky. Values are unchanged.

extension StatusCategory {
    var tvLabel: String {
        switch self {
        case .open: return "Open"
        case .limited: return "Limited"
        case .closed: return "Closed"
        }
    }

    var tvIcon: String {
        switch self {
        case .open: return "checkmark.circle.fill"
        case .limited: return "exclamationmark.triangle.fill"
        case .closed: return "xmark.circle.fill"
        }
    }
}
