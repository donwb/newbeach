//
//  BeachRampTVTests.swift
//  BeachRampTVTests
//
//  Created by Don Browning on 3/11/26.
//

import Testing
import BeachStatus
@testable import BeachRampTV

struct TVSkyGroundTests {

    /// Every ground the sun can produce must stay dark enough to hold
    /// #F3F2F2 type and #F0DDB4 accents — the design's one hard constraint
    /// on the sixteen day-part gradients. Sampled across the full altitude
    /// range at 2° steps on both tracks, not just at the anchors, so an
    /// interpolated midpoint can never sneak above the ceiling.
    @Test func groundsStayDarkAcrossTheWholeDay() {
        // The brightest pinned anchor channel is 0x48 (golden evening
        // bottom); leave interpolation a little headroom, none for drift.
        let ceiling = 0x50.asUnit

        for rising in [true, false] {
            var altitude = -25.0
            while altitude <= 55.0 {
                let ground = TVSkyGround.forSun(altitude: altitude, isRising: rising)
                for stop in [ground.top, ground.bottom] {
                    for channel in [stop.r, stop.g, stop.b] {
                        #expect(channel <= ceiling,
                                "channel \(channel) above ceiling at altitude \(altitude), rising \(rising)")
                    }
                }
                altitude += 2
            }
        }
    }

    /// The three mock-pinned anchors survive verbatim.
    @Test func pinnedAnchorsMatchTheMock() {
        #expect(TVSkyGround.noon.top.hex == 0x0A1A24)
        #expect(TVSkyGround.noon.bottom.hex == 0x0F2C3C)
        #expect(TVSkyGround.goldenEvening.top.hex == 0x20130A)
        #expect(TVSkyGround.goldenEvening.bottom.hex == 0x48230F)
        #expect(TVSkyGround.night.top.hex == 0x06060D)
        #expect(TVSkyGround.night.bottom.hex == 0x111328)
    }
}

private extension Int {
    var asUnit: Double { Double(self) / 255 }
}

private extension SkyStop {
    var hex: Int {
        (Int((r * 255).rounded()) << 16) | (Int((g * 255).rounded()) << 8) | Int((b * 255).rounded())
    }
}
