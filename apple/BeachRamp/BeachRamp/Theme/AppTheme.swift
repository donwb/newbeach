import SwiftUI
import UIKit
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

/// Colors that adapt between light and dark mode. These intentionally use
/// semantic system colors so surfaces flip automatically; previously these were
/// hardcoded near-white, which made adaptive `.primary` text invisible in dark mode.
struct AppColors {
    static let background = Color(.systemBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemBackground)
    /// One elevation up from `cardBackground`, for cards nested inside a card.
    static let nestedCardBackground = Color(.tertiarySystemBackground)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let separator = Color(.separator)

    /// Brand teal tuned for legibility in both modes — brighter in the dark.
    /// Centralizes the ad-hoc `colorScheme == .dark ? .ocean500 : .ocean600`
    /// pattern that lived in `TideChartView`.
    static let oceanAccent = Color(uiColor: UIColor { trait in
        UIColor(trait.userInterfaceStyle == .dark ? Color.ocean500 : Color.ocean600)
    })

    /// Time-of-day header banner gradient (see `HeaderSky`).
    static var headerGradient: LinearGradient { HeaderSky.current().gradient }
}

// MARK: - Time-of-Day Header Sky

/// One RGB gradient stop, stored as components so palettes interpolate numerically.
private struct HeaderStop {
    var r, g, b: Double
    init(_ hex: Int) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
    private init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    var color: Color { Color(red: r, green: g, blue: b) }

    func mixed(with other: HeaderStop, _ t: Double) -> HeaderStop {
        HeaderStop(r: r + (other.r - r) * t,
                   g: g + (other.g - g) * t,
                   b: b + (other.b - b) * t)
    }
}

/// A two-stop header banner gradient that tracks the real sun for New Smyrna
/// Beach — the iPhone/iPad cousin of the tvOS `SkyPalette`. The top stop always
/// stays a deep, saturated teal so the white header text remains legible at every
/// hour; only the bottom stop carries the time-of-day hue (warm at dawn/dusk,
/// bright at midday, deep at night). Reuses the shared, tested `SolarCalculator`.
struct HeaderSky {
    fileprivate let top: HeaderStop
    fileprivate let bottom: HeaderStop

    var gradient: LinearGradient {
        LinearGradient(colors: [top.color, bottom.color],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    fileprivate init(top: HeaderStop, bottom: HeaderStop) {
        self.top = top
        self.bottom = bottom
    }

    /// The header sky for right now at New Smyrna Beach.
    static func current(date: Date = Date()) -> HeaderSky {
        let solar = SolarCalculator.newSmyrnaBeach
        return forSun(altitude: solar.altitude(at: date), isRising: solar.isRising(at: date))
    }

    // Rising (morning) and falling (evening) tracks share night/noon endpoints so
    // the rising↔falling flip at the solar extremes is seamless, while dawn reads
    // cooler and dusk warmer — mirroring the TV's phase model.
    private static let risingAnchors: [(altitude: Double, sky: HeaderSky)] = [
        (-10, HeaderSky(top: HeaderStop(0x0B3D3B), bottom: HeaderStop(0x10303F))), // night
        (-2,  HeaderSky(top: HeaderStop(0x115E59), bottom: HeaderStop(0xB56B4E))), // sunrise
        (22,  HeaderSky(top: HeaderStop(0x0F766E), bottom: HeaderStop(0x0D9488))), // morning
        (45,  HeaderSky(top: HeaderStop(0x0D9488), bottom: HeaderStop(0x14B8A6))), // noon
    ]
    private static let fallingAnchors: [(altitude: Double, sky: HeaderSky)] = [
        (-10, HeaderSky(top: HeaderStop(0x0B3D3B), bottom: HeaderStop(0x10303F))), // night
        (-6,  HeaderSky(top: HeaderStop(0x123E4A), bottom: HeaderStop(0x3A2C55))), // evening
        (-1,  HeaderSky(top: HeaderStop(0x115E59), bottom: HeaderStop(0xC25A2E))), // sunset
        (22,  HeaderSky(top: HeaderStop(0x0F766E), bottom: HeaderStop(0xB07B33))), // afternoon
        (45,  HeaderSky(top: HeaderStop(0x0D9488), bottom: HeaderStop(0x14B8A6))), // noon
    ]

    static func forSun(altitude: Double, isRising: Bool) -> HeaderSky {
        let anchors = isRising ? risingAnchors : fallingAnchors
        if altitude <= anchors.first!.altitude { return anchors.first!.sky }
        if altitude >= anchors.last!.altitude { return anchors.last!.sky }

        for i in 0..<(anchors.count - 1) {
            let lower = anchors[i]
            let upper = anchors[i + 1]
            if altitude >= lower.altitude && altitude <= upper.altitude {
                let t = (altitude - lower.altitude) / (upper.altitude - lower.altitude)
                return HeaderSky(top: lower.sky.top.mixed(with: upper.sky.top, t),
                                 bottom: lower.sky.bottom.mixed(with: upper.sky.bottom, t))
            }
        }
        return anchors.last!.sky
    }
}

// MARK: - Card Surface

/// Standard card surface: adaptive fill, continuous corners, and a whisper of a
/// shadow that's near-invisible in dark mode. Centralizes the repeated
/// `.background { RoundedRectangle(...).fill(AppColors.cardBackground) }`.
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppColors.cardBackground)
            }
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}
