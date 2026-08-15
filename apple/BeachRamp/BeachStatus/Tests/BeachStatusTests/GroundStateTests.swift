import Foundation
import Testing
@testable import BeachStatus

struct GroundStateTests {
    private static let eastern = TimeZone(identifier: "America/New_York")!

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: Self.eastern,
            year: 2026, month: month, day: day, hour: hour, minute: minute
        ).date!
    }

    // dayness = clamp((altitude + 4) / 12, 0, 1)

    @Test func daynessBoundaries() {
        // Midday in August: sun well above +8° → full day.
        let noon = GroundState.compute(at: date(8, 14, 13, 0))
        #expect(noon.dayness == 1)
        #expect(noon.isDay)

        // Midnight: sun far below −4° → full night.
        let midnight = GroundState.compute(at: date(8, 14, 0, 30))
        #expect(midnight.dayness == 0)
        #expect(!midnight.isDay)
    }

    @Test func daynessIsMonotonicThroughDusk() {
        // Sample across the evening; dayness must never increase.
        var previous = Double.infinity
        for minutes in stride(from: 0, through: 4 * 60, by: 10) {
            let state = GroundState.compute(at: date(8, 14, 18, 0).addingTimeInterval(TimeInterval(minutes * 60)))
            #expect(state.dayness <= previous)
            previous = state.dayness
        }
    }

    @Test func tokensFlipAtHalf() {
        // Sweep a day at minute resolution: tokens must be day exactly when
        // dayness >= 0.5. (Guards against an interpolating regression.)
        for minutes in stride(from: 0, to: 24 * 60, by: 30) {
            let state = GroundState.compute(at: date(8, 14, 0, 0).addingTimeInterval(TimeInterval(minutes * 60)))
            #expect(state.isDay == (state.dayness >= 0.5))
        }
    }

    @Test func phaseNameSnapsToAnchor() {
        let night = GroundState.compute(at: date(8, 14, 1, 0))
        #expect(night.palette.phaseName == "Night")

        // Mid-August mid-afternoon: falling track, altitude in the 20–48 band.
        let afternoon = GroundState.compute(at: date(8, 14, 16, 12))
        #expect(!afternoon.isRising)
        #expect(["Afternoon", "Early afternoon", "Noon", "Golden evening"].contains(afternoon.palette.phaseName))
    }

    @Test func veilVanishesAtNight() {
        let midnight = GroundState.compute(at: date(8, 14, 0, 30))
        #expect(midnight.dayness == 0)
        // Veil opacity is dayness — at 0 the sheet stops existing as a surface.
        // (Color equality on opacity isn't directly inspectable; the dayness
        // value is the contract.)
    }
}
