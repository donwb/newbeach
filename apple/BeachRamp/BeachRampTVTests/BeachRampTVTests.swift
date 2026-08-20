//
//  BeachRampTVTests.swift
//  BeachRampTVTests
//
//  Created by Don Browning on 3/11/26.
//

import Foundation
import Testing
import BeachStatus
@testable import BeachRampTV

/// The ground is the shared full-brightness SkyPalette; TVSky's ink veils
/// are what keep type legible on it. These tests pin that contract: for
/// every sky the sun can produce — sampled at 2° steps on both tracks, not
/// just at the anchors — the veiled ground under the ledger and header must
/// hold #F3F2F2 type (and sand accents in the header) at large-text
/// contrast. If a SkyPalette phase brightens or a veil opacity is turned
/// down past legibility, this fails before the sim does.
struct TVSkyVeilTests {

    /// sRGB relative luminance of an (r, g, b) triple in 0…1 units.
    private func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func lin(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG contrast ratio between a foreground and background luminance.
    private func contrast(_ lighter: Double, _ darker: Double) -> Double {
        (max(lighter, darker) + 0.05) / (min(lighter, darker) + 0.05)
    }

    /// A sky stop seen through the veil ink (0x041A28) at `opacity`.
    private func veiled(_ stop: SkyStop, opacity: Double) -> Double {
        let ink = (r: 0x04.asUnit, g: 0x1A.asUnit, b: 0x28.asUnit)
        return luminance(
            stop.r * (1 - opacity) + ink.r * opacity,
            stop.g * (1 - opacity) + ink.g * opacity,
            stop.b * (1 - opacity) + ink.b * opacity
        )
    }

    private let typeLuminance = { () -> Double in
        let c = 0xF3.asUnit
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c) + 0.7152 * lin(c) + 0.0722 * lin(c)
    }()

    private var sandLuminance: Double {
        luminance(0xF0.asUnit, 0xDD.asUnit, 0xB4.asUnit)
    }

    /// The ledger's densest type (24px table rows) sits toward the screen
    /// bottom, where the veil is heaviest and the sky palest — the worst
    /// pairing is the sky's bottom stop under the bottom veil opacity, but
    /// the veil is a gradient, so the top of the region is checked against
    /// the lighter top opacity too (against the mid stop that region shows).
    @Test func ledgerTypeHoldsOnEverySky() {
        for rising in [true, false] {
            var altitude = -25.0
            while altitude <= 55.0 {
                let sky = SkyPalette.forSun(altitude: altitude, isRising: rising)
                let bottom = veiled(sky.bottomStop, opacity: TVSky.ledgerVeilBottomOpacity)
                #expect(contrast(typeLuminance, bottom) >= 3.5,
                        "ledger bottom under-contrast at altitude \(altitude), rising \(rising)")
                let upper = veiled(sky.midStop, opacity: TVSky.ledgerVeilTopOpacity)
                #expect(contrast(typeLuminance, upper) >= 3.0,
                        "ledger top under-contrast at altitude \(altitude), rising \(rising)")
                altitude += 2
            }
        }
    }

    /// The header's worst corner is top-right, roughly the sky's mid stop
    /// under the flat header veil; both white type and the sand outlook
    /// button must hold there.
    @Test func headerTypeAndSandHoldOnEverySky() {
        for rising in [true, false] {
            var altitude = -25.0
            while altitude <= 55.0 {
                let sky = SkyPalette.forSun(altitude: altitude, isRising: rising)
                let ground = veiled(sky.midStop, opacity: TVSky.headerVeilOpacity)
                #expect(contrast(typeLuminance, ground) >= 3.0,
                        "header type under-contrast at altitude \(altitude), rising \(rising)")
                #expect(contrast(sandLuminance, ground) >= 2.4,
                        "header sand accent under-contrast at altitude \(altitude), rising \(rising)")
                altitude += 2
            }
        }
    }
}

private extension Int {
    var asUnit: Double { Double(self) / 255 }
}
