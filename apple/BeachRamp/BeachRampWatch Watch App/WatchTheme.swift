import SwiftUI
import BeachStatus

// MARK: - Watch Color Palette

extension Color {
    static let ocean500 = Color(red: 0.08, green: 0.72, blue: 0.65)
    static let ocean600 = Color(red: 0.05, green: 0.58, blue: 0.53)
    static let ocean700 = Color(red: 0.06, green: 0.46, blue: 0.43)

    static let watchStatusOpen = Color(red: 0.06, green: 0.73, blue: 0.51)
    static let watchStatusLimited = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let watchStatusClosed = Color(red: 0.94, green: 0.27, blue: 0.27)
}

extension StatusCategory {
    var watchColor: Color {
        switch self {
        case .open: return .watchStatusOpen
        case .limited: return .watchStatusLimited
        case .closed: return .watchStatusClosed
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
