import SwiftUI

// The sun-following sky. Sixteen moods of the day shared by tvOS, iOS,
// widgets, and the web port (web/js/sky.js) — the four stay in step by
// construction, so a value change here must land there too.

/// One RGB gradient stop, stored as components so palettes can be interpolated
/// numerically without resolving SwiftUI colors.
public struct SkyStop: Sendable {
    public var r, g, b: Double

    public init(_ hex: Int) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    private init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    public var color: Color { Color(red: r, green: g, blue: b) }

    public func mixed(with other: SkyStop, fraction t: Double) -> SkyStop {
        SkyStop(r: r + (other.r - r) * t,
                g: g + (other.g - g) * t,
                b: b + (other.b - b) * t)
    }
}

/// A three-stop background gradient plus a dimming factor, derived from the
/// sun's altitude so each surface's "sky" tracks the real sun through the day:
/// deep night → dawn/dusk twilight → golden hour → bright midday, and back.
public struct SkyPalette: Sendable {
    public let topStop: SkyStop
    public let midStop: SkyStop
    public let bottomStop: SkyStop
    /// 1.0 = full brightness (day); lower values darken the whole board at night.
    public let dimming: Double
    /// Human-readable phase, snapped to the nearer anchor ("Afternoon", "Civil dusk").
    public let phaseName: String

    /// Gradient used as the tvOS full-screen background.
    public var gradient: LinearGradient {
        LinearGradient(
            colors: [topStop.color, midStop.color, bottomStop.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Opacity of a black scrim laid over the board to dim it (0 = none).
    public var dimOverlayOpacity: Double { 1 - dimming }

    private init(name: String, top: SkyStop, mid: SkyStop, bottom: SkyStop, dimming: Double) {
        phaseName = name
        topStop = top
        midStop = mid
        bottomStop = bottom
        self.dimming = dimming
    }

    // MARK: Named phase palettes

    // Sixteen moods of the day: nine on the rising track, seven falling, with
    // night and noon shared so the rising↔falling flip (which only occurs at
    // the solar extremes) is seamless. The three twilight steps per side —
    // astronomical, nautical, civil — are the point: the old model's lowest
    // anchor was −10°, which collapsed ~90 minutes of twilight into one flat
    // night. Mornings run cool and fresh, evenings warm and rich.
    private static let night = SkyPalette(name: "Night",          // sun below −18°
        top: SkyStop(0x070A14), mid: SkyStop(0x101830), bottom: SkyStop(0x1C2A44), dimming: 0.55)

    // Rising track
    private static let astronomicalDawn = SkyPalette(name: "Astronomical dawn",
        top: SkyStop(0x080C1A), mid: SkyStop(0x141C38), bottom: SkyStop(0x26304E), dimming: 0.58)
    private static let nauticalDawn = SkyPalette(name: "Nautical dawn",
        top: SkyStop(0x0C1230), mid: SkyStop(0x22265A), bottom: SkyStop(0x3E3A6B), dimming: 0.64)
    private static let civilDawn = SkyPalette(name: "Civil dawn",
        top: SkyStop(0x142046), mid: SkyStop(0x4A4478), bottom: SkyStop(0x8E6A82), dimming: 0.74)
    private static let sunrise = SkyPalette(name: "Sunrise",      // cool indigo top, warm peach horizon
        top: SkyStop(0x1B2A52), mid: SkyStop(0x6A5C8E), bottom: SkyStop(0xF2B07A), dimming: 0.85)
    private static let goldenMorning = SkyPalette(name: "Golden morning",
        top: SkyStop(0x17456B), mid: SkyStop(0x3E7C9E), bottom: SkyStop(0xF0C48E), dimming: 0.92)
    private static let morning = SkyPalette(name: "Morning",      // fresh, clear cool blue
        top: SkyStop(0x0E6E8C), mid: SkyStop(0x1F9BBF), bottom: SkyStop(0x9CD8E8), dimming: 1.0)
    private static let lateMorning = SkyPalette(name: "Late morning",
        top: SkyStop(0x0E779A), mid: SkyStop(0x29A6C6), bottom: SkyStop(0xA8DEEC), dimming: 1.0)
    private static let noon = SkyPalette(name: "Noon",            // brightest, high overhead sun
        top: SkyStop(0x0E7FA8), mid: SkyStop(0x33B0CC), bottom: SkyStop(0xB2E6F0), dimming: 1.0)

    // Falling track
    private static let astronomicalDusk = SkyPalette(name: "Astronomical dusk",
        top: SkyStop(0x080D1C), mid: SkyStop(0x1A1C3A), bottom: SkyStop(0x3A2942), dimming: 0.62)
    private static let nauticalDusk = SkyPalette(name: "Nautical dusk",
        top: SkyStop(0x0A1228), mid: SkyStop(0x2E2A52), bottom: SkyStop(0x6E3C58), dimming: 0.72)
    private static let civilDusk = SkyPalette(name: "Civil dusk",
        top: SkyStop(0x0E2840), mid: SkyStop(0x5E4055), bottom: SkyStop(0xB45C50), dimming: 0.80)
    private static let sunset = SkyPalette(name: "Sunset",        // rich, saturated orange horizon
        top: SkyStop(0x123A52), mid: SkyStop(0x9A5E50), bottom: SkyStop(0xF08A46), dimming: 0.9)
    private static let goldenEvening = SkyPalette(name: "Golden evening",
        top: SkyStop(0x145066), mid: SkyStop(0x6F7A66), bottom: SkyStop(0xE8A85E), dimming: 0.94)
    private static let afternoon = SkyPalette(name: "Afternoon",  // teal warmed with gold
        top: SkyStop(0x10657F), mid: SkyStop(0x3F957E), bottom: SkyStop(0xD9BC72), dimming: 0.98)
    private static let earlyAfternoon = SkyPalette(name: "Early afternoon",
        top: SkyStop(0x0F7294), mid: SkyStop(0x39A5A5), bottom: SkyStop(0xC5D6B1), dimming: 0.99)

    // Anchors keyed by sun altitude (degrees), ordered low → high. We pick the
    // track from the sun's direction, then linearly interpolate between
    // bracketing anchors so transitions are continuous rather than snapping.
    // Twilight anchors sit at the standard solar angles: −18° astronomical,
    // −13/−9/−5 between, −0.8° at the visible sunrise/sunset.
    private static let risingAnchors: [(altitude: Double, palette: SkyPalette)] = [
        (-18, night), (-13, astronomicalDawn), (-9, nauticalDawn), (-5, civilDawn),
        (-0.8, sunrise), (6, goldenMorning), (20, morning), (34, lateMorning), (48, noon),
    ]
    private static let fallingAnchors: [(altitude: Double, palette: SkyPalette)] = [
        (-18, night), (-13, astronomicalDusk), (-9, nauticalDusk), (-5, civilDusk),
        (-0.8, sunset), (6, goldenEvening), (20, afternoon), (34, earlyAfternoon), (48, noon),
    ]

    /// Build the palette for a given sun altitude (degrees) and direction.
    /// `isRising` selects the morning vs. evening color track.
    public static func forSun(altitude: Double, isRising: Bool) -> SkyPalette {
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
            name: t < 0.5 ? phaseName : other.phaseName,
            top: topStop.mixed(with: other.topStop, fraction: t),
            mid: midStop.mixed(with: other.midStop, fraction: t),
            bottom: bottomStop.mixed(with: other.bottomStop, fraction: t),
            dimming: dimming + (other.dimming - dimming) * t
        )
    }

    // MARK: Night-muted status colors

    /// How far into night the sky is: 0 across the bright-day range,
    /// 1 at deep night (dimming 0.55).
    public var nightness: Double { min(1, max(0, (1 - dimming) / 0.45)) }

    /// Board status color, muted toward the night sky after dark. The dim
    /// scrim only darkens — it can't desaturate — so an unblended closed
    /// field glows against the near-black sky all night. Overlays keep raw
    /// `statusColor`: they render above the scrim as opaque designed fields.
    public func statusColor(for category: StatusCategory) -> Color {
        let c = category.statusRGB
        let t = 0.35 * nightness
        // Blend target: the night palette's mid stop (#101830).
        let night = SkyStop(0x101830)
        return Color(
            red: c.red + (night.r - c.red) * t,
            green: c.green + (night.g - c.green) * t,
            blue: c.blue + (night.b - c.blue) * t
        )
    }
}

/// The current sky, injected at the root so status surfaces can mute with
/// the sun. Defaults to full noon for previews.
private struct SkyPaletteKey: EnvironmentKey {
    static let defaultValue = SkyPalette.forSun(altitude: 48, isRising: true)
}

public extension EnvironmentValues {
    var skyPalette: SkyPalette {
        get { self[SkyPaletteKey.self] }
        set { self[SkyPaletteKey.self] = newValue }
    }
}
