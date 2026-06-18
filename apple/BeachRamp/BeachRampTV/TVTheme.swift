import SwiftUI
import BeachStatus

// MARK: - TV Color Palette (large screen optimized)

extension Color {
    static let tvOcean500 = Color(red: 0.08, green: 0.72, blue: 0.65)
    static let tvOcean600 = Color(red: 0.05, green: 0.58, blue: 0.53)
    static let tvOcean700 = Color(red: 0.06, green: 0.46, blue: 0.43)
    static let tvOcean800 = Color(red: 0.07, green: 0.37, blue: 0.35)

    static let tvSand50 = Color(red: 1.0, green: 0.99, blue: 0.95)

    static let tvStatusOpen = Color(red: 0.20, green: 0.90, blue: 0.40)
    static let tvStatusLimited = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let tvStatusClosed = Color(red: 0.94, green: 0.27, blue: 0.27)
}

// MARK: - Time-of-Day Sky

/// One RGB gradient stop, stored as components so palettes can be interpolated
/// numerically (SwiftUI's `Color.mix` is tvOS 18+, and we target tvOS 17).
private struct SkyStop {
    var r, g, b: Double
    init(_ hex: Int) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
    private init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    var color: Color { Color(red: r, green: g, blue: b) }

    func mixed(with other: SkyStop, fraction t: Double) -> SkyStop {
        SkyStop(r: r + (other.r - r) * t,
                g: g + (other.g - g) * t,
                b: b + (other.b - b) * t)
    }
}

/// A three-stop background gradient plus a dimming factor, derived from the
/// sun's altitude so the dashboard's "sky" tracks the real sun through the day:
/// deep night → dawn/dusk twilight → golden hour → bright midday, and back.
struct SkyPalette {
    fileprivate let topStop: SkyStop
    fileprivate let midStop: SkyStop
    fileprivate let bottomStop: SkyStop
    /// 1.0 = full brightness (day); lower values darken the whole board at night.
    let dimming: Double

    /// Gradient used as the full-screen background.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [topStop.color, midStop.color, bottomStop.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Opacity of a black scrim laid over the board to dim it (0 = none).
    var dimOverlayOpacity: Double { 1 - dimming }

    fileprivate init(top: SkyStop, mid: SkyStop, bottom: SkyStop, dimming: Double) {
        self.topStop = top
        self.midStop = mid
        self.bottomStop = bottom
        self.dimming = dimming
    }

    // MARK: Named phase palettes

    // The seven moods of the day. Night and noon are shared between the rising
    // and falling tracks so the rising↔falling flip (which only occurs at the
    // solar-noon and solar-midnight extremes) is seamless. Dawn and dusk diverge:
    // mornings run cool and fresh, afternoons warm, sunsets richer than sunrises.
    private static let night = SkyPalette(      // sun well below the horizon
        top: SkyStop(0x070A14), mid: SkyStop(0x101830), bottom: SkyStop(0x1C2A44), dimming: 0.55)
    private static let sunrise = SkyPalette(    // cool indigo top, warm peach horizon
        top: SkyStop(0x1B2A52), mid: SkyStop(0x6A5C8E), bottom: SkyStop(0xF2B07A), dimming: 0.85)
    private static let morning = SkyPalette(    // fresh, clear cool blue
        top: SkyStop(0x0E6E8C), mid: SkyStop(0x1F9BBF), bottom: SkyStop(0x9CD8E8), dimming: 1.0)
    private static let noon = SkyPalette(       // brightest, high overhead sun
        top: SkyStop(0x0E7FA8), mid: SkyStop(0x33B0CC), bottom: SkyStop(0xB2E6F0), dimming: 1.0)
    private static let afternoon = SkyPalette(  // teal warmed with gold
        top: SkyStop(0x10657F), mid: SkyStop(0x3F957E), bottom: SkyStop(0xD9BC72), dimming: 0.98)
    private static let sunset = SkyPalette(     // rich, saturated orange horizon
        top: SkyStop(0x123A52), mid: SkyStop(0x9A5E50), bottom: SkyStop(0xF08A46), dimming: 0.9)
    private static let evening = SkyPalette(    // dusky mauve/indigo fading to night
        top: SkyStop(0x0A1228), mid: SkyStop(0x2E2A52), bottom: SkyStop(0x6E3C58), dimming: 0.72)

    // Anchors keyed by sun altitude (degrees), ordered low → high. The day is
    // split into a rising track (night → sunrise → morning → noon) and a falling
    // track (noon → afternoon → sunset → evening → night). We pick the track from
    // the sun's direction, then linearly interpolate between bracketing anchors so
    // transitions are continuous rather than snapping between fixed phases.
    private static let risingAnchors: [(altitude: Double, palette: SkyPalette)] = [
        (-10, night), (-2, sunrise), (22, morning), (45, noon),
    ]
    private static let fallingAnchors: [(altitude: Double, palette: SkyPalette)] = [
        (-10, night), (-6, evening), (-1, sunset), (22, afternoon), (45, noon),
    ]

    /// Build the palette for a given sun altitude (degrees) and direction.
    /// `isRising` selects the morning vs. evening color track.
    static func forSun(altitude: Double, isRising: Bool) -> SkyPalette {
        let anchors = isRising ? Self.risingAnchors : Self.fallingAnchors
        if altitude <= anchors.first!.altitude { return anchors.first!.palette }
        if altitude >= anchors.last!.altitude { return anchors.last!.palette }

        for i in 0..<(anchors.count - 1) {
            let lower = anchors[i]
            let upper = anchors[i + 1]
            if altitude >= lower.altitude && altitude <= upper.altitude {
                let t = (altitude - lower.altitude) / (upper.altitude - lower.altitude)
                return lower.palette.blended(toward: upper.palette, fraction: t)
            }
        }
        return anchors.last!.palette
    }

    private func blended(toward other: SkyPalette, fraction t: Double) -> SkyPalette {
        SkyPalette(
            top: topStop.mixed(with: other.topStop, fraction: t),
            mid: midStop.mixed(with: other.midStop, fraction: t),
            bottom: bottomStop.mixed(with: other.bottomStop, fraction: t),
            dimming: dimming + (other.dimming - dimming) * t
        )
    }
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
