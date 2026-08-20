import SwiftUI
import BeachStatus

/// The video-first screen's ground: the shared SkyPalette's sixteen solar
/// phases, re-voiced as dark two-stop gradients at roughly a fifth of full
/// saturation, so #F3F2F2 type and #F0DDB4 accents hold on every one of them
/// and the beach stays the brightest thing on screen.
///
/// Deliberately tvOS-local rather than a parallel track in the shared
/// SkyPalette: the dark ambient voice is a TV presentation decision, and the
/// shared file carries a web-parity obligation (web/js/sky.js) this track
/// must not inherit. The anchor *altitudes* and interpolation mirror
/// SkyPalette exactly; only the colors differ. Three anchors are pinned
/// verbatim from the design handoff (noon, golden evening, night); the rest
/// are the corresponding SkyPalette hues hand-darkened offline so every
/// phase is a reviewable constant. The unit test samples the whole
/// interpolated range and enforces the darkness ceiling.
struct TVSkyGround {
    let top: SkyStop
    let bottom: SkyStop

    /// CSS 178deg — effectively vertical with a 2° tilt.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [top.color, bottom.color],
            startPoint: UnitPoint(x: 0.53, y: 0),
            endPoint: UnitPoint(x: 0.47, y: 1)
        )
    }

    private init(_ topHex: Int, _ bottomHex: Int) {
        top = SkyStop(topHex)
        bottom = SkyStop(bottomHex)
    }

    // Anchors keyed by sun altitude (degrees), same keys as SkyPalette:
    // −18 / −13 / −9 / −5 / −0.8 / 6 / 20 / 34 / 48, rising and falling
    // tracks with night and noon shared.
    static let night = TVSkyGround(0x06060D, 0x111328)            // pinned (mock)
    static let noon = TVSkyGround(0x0A1A24, 0x0F2C3C)             // pinned (mock)
    static let goldenEvening = TVSkyGround(0x20130A, 0x48230F)    // pinned (mock)

    static let astronomicalDawn = TVSkyGround(0x070811, 0x131630)
    static let nauticalDawn = TVSkyGround(0x0A0A18, 0x1A1838)
    static let civilDawn = TVSkyGround(0x0E1024, 0x2A2040)
    static let sunrise = TVSkyGround(0x121327, 0x3A2A26)
    static let goldenMorning = TVSkyGround(0x0E1A22, 0x2E2A1C)
    static let morning = TVSkyGround(0x0A161E, 0x10262E)
    static let lateMorning = TVSkyGround(0x0A1822, 0x0E2A38)

    static let astronomicalDusk = TVSkyGround(0x08070F, 0x16122C)
    static let nauticalDusk = TVSkyGround(0x0C0A16, 0x221631)
    static let civilDusk = TVSkyGround(0x120D16, 0x2E1A22)
    static let sunset = TVSkyGround(0x180E0C, 0x3C1E12)
    static let afternoon = TVSkyGround(0x0E191C, 0x1E2C26)
    static let earlyAfternoon = TVSkyGround(0x0C1A20, 0x163034)

    static let risingAnchors: [(altitude: Double, ground: TVSkyGround)] = [
        (-18, night), (-13, astronomicalDawn), (-9, nauticalDawn), (-5, civilDawn),
        (-0.8, sunrise), (6, goldenMorning), (20, morning), (34, lateMorning), (48, noon),
    ]
    static let fallingAnchors: [(altitude: Double, ground: TVSkyGround)] = [
        (-18, night), (-13, astronomicalDusk), (-9, nauticalDusk), (-5, civilDusk),
        (-0.8, sunset), (6, goldenEvening), (20, afternoon), (34, earlyAfternoon), (48, noon),
    ]

    /// The ground for a given sun position — same interpolation contract as
    /// `SkyPalette.forSun`, so the two never disagree about the phase.
    static func forSun(altitude: Double, isRising: Bool) -> TVSkyGround {
        let anchors = isRising ? risingAnchors : fallingAnchors
        if altitude <= anchors.first!.altitude { return anchors.first!.ground }
        if altitude >= anchors.last!.altitude { return anchors.last!.ground }

        for i in 0..<(anchors.count - 1) {
            let lower = anchors[i]
            let upper = anchors[i + 1]
            if altitude >= lower.altitude && altitude <= upper.altitude {
                let t = (altitude - lower.altitude) / (upper.altitude - lower.altitude)
                return TVSkyGround(
                    top: lower.ground.top.mixed(with: upper.ground.top, fraction: t),
                    bottom: lower.ground.bottom.mixed(with: upper.ground.bottom, fraction: t)
                )
            }
        }
        return anchors.last!.ground
    }

    private init(top: SkyStop, bottom: SkyStop) {
        self.top = top
        self.bottom = bottom
    }
}
