import SwiftUI
import BeachStatus

// MARK: - TV Color Palette (large screen optimized)

extension Color {
    static let tvOcean500 = Color(red: 0.08, green: 0.72, blue: 0.65)
    static let tvOcean600 = Color(red: 0.05, green: 0.58, blue: 0.53)
    static let tvOcean700 = Color(red: 0.06, green: 0.46, blue: 0.43)
    static let tvOcean800 = Color(red: 0.07, green: 0.37, blue: 0.35)

    static let tvSand50 = Color(red: 1.0, green: 0.99, blue: 0.95)

    static let tvStatusOpen = Color(red: 0.06, green: 0.73, blue: 0.51)
    static let tvStatusLimited = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let tvStatusClosed = Color(red: 0.94, green: 0.27, blue: 0.27)
}

extension StatusCategory {
    var tvColor: Color {
        switch self {
        case .open: return .tvStatusOpen
        case .limited: return .tvStatusLimited
        case .closed: return .tvStatusClosed
        }
    }

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
