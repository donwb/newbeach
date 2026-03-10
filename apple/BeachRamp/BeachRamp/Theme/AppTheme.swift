import SwiftUI
import BeachStatus

// MARK: - Color Palette

/// Beach-themed color palette matching the web app.
extension Color {
    // MARK: Ocean (primary teal)
    static let ocean50  = Color(hex: 0xF0FDFA)
    static let ocean100 = Color(hex: 0xCCFBF1)
    static let ocean500 = Color(hex: 0x14B8A6)
    static let ocean600 = Color(hex: 0x0D9488)
    static let ocean700 = Color(hex: 0x0F766E)
    static let ocean800 = Color(hex: 0x115E59)
    static let ocean900 = Color(hex: 0x134E4A)

    // MARK: Sand (warm background)
    static let sand50  = Color(hex: 0xFEFCF3)
    static let sand100 = Color(hex: 0xFDF6E3)
    static let sand200 = Color(hex: 0xF9E8C0)
    static let sand300 = Color(hex: 0xF4D68A)

    // MARK: Status
    static let statusOpen    = Color(hex: 0x10B981) // emerald-500
    static let statusLimited = Color(hex: 0xF59E0B) // amber-500
    static let statusClosed  = Color(hex: 0xEF4444) // red-500

    // MARK: Tide chart
    static let tideHigh = Color(hex: 0x0D9488) // ocean-600
    static let tideLow  = Color(hex: 0x6366F1) // indigo-500
    static let tideNow  = Color(hex: 0xD97706) // amber-600

    // MARK: Hex initializer
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Status Category Colors

extension StatusCategory {
    var color: Color {
        switch self {
        case .open: return .statusOpen
        case .limited: return .statusLimited
        case .closed: return .statusClosed
        }
    }

    var label: String {
        switch self {
        case .open: return "Open"
        case .limited: return "Limited"
        case .closed: return "Closed"
        }
    }

    var iconName: String {
        switch self {
        case .open: return "checkmark.circle.fill"
        case .limited: return "exclamationmark.triangle.fill"
        case .closed: return "xmark.circle.fill"
        }
    }
}

// MARK: - Adaptive Colors

/// Colors that adapt between light and dark mode.
struct AppColors {
    static let background = Color(red: 1, green: 1, blue: 1)
    static let cardBackground = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let separator = Color.gray.opacity(0.3)

    /// The sand-colored background used in light mode.
    static let sandBackground = Color.sand50

    /// Gradient for the app header.
    static let headerGradient = LinearGradient(
        colors: [.ocean700, .ocean600],
        startPoint: .leading,
        endPoint: .trailing
    )
}
