import Foundation
import Testing
@testable import BeachStatus

/// Pins the verdict copy for every scenario in the tvOS design handoff
/// (August design_handoff_tvos_board/README.md), plus the edge cases the
/// mock doesn't show.
struct VerdictBuilderTests {
    private static let eastern = TimeZone(identifier: "America/New_York")!

    /// A moment on the mock's captured day: 2026-08-14 (a Friday), Eastern.
    private func at(_ hour: Int, _ minute: Int, day: Int = 14) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: Self.eastern,
            year: 2026, month: 8, day: day, hour: hour, minute: minute
        ).date!
    }

    private func ramp(_ name: String, _ status: String, since: Date? = nil) -> Ramp {
        Ramp(id: name.hashValue & 0xFFFF, rampName: name, accessStatus: status,
             statusCategory: StatusCategory(accessStatus: status).rawValue,
             objectID: 0, city: "NEW SMYRNA BEACH", accessID: name,
             location: "", lastUpdated: nil, statusSince: since)
    }

    /// The five NSB ramps, all open since 6:02 AM (27th Av since yesterday).
    private func allOpen() -> [Ramp] {
        [
            ramp("BEACHWAY AV", "OPEN", since: at(6, 2)),
            ramp("CRAWFORD RD", "OPEN", since: at(6, 2)),
            ramp("FLAGLER AV", "OPEN", since: at(6, 2)),
            ramp("3RD AV", "OPEN", since: at(6, 2)),
            ramp("27TH AV", "OPEN", since: at(16, 11, day: 13)),
        ]
    }

    private func tide(direction: String, predictions: [TidePrediction]) -> TideInfo {
        TideInfo(tideDirection: direction, tidePercentage: 50, predictions: predictions)
    }

    // MARK: README scenario: All open

    @Test func allOpenScenario() {
        let now = at(13, 30)
        let verdict = VerdictBuilder.build(
            ramps: allOpen(),
            tide: tide(direction: "Falling",
                       predictions: [TidePrediction(time: at(16, 57), type: "L", height: -0.1)]),
            sunset: at(19, 11),
            now: now
        )
        #expect(verdict.category == .open)
        #expect(verdict.headline == "All five open")
        #expect(verdict.subline == "Tide dropping · low 4:57 PM · 5h 41m of light left")
    }

    // MARK: README scenario: Crawford closed

    @Test func singleClosedScenario() {
        var ramps = allOpen()
        ramps[1] = ramp("CRAWFORD RD", "CLOSED FOR HIGH TIDE", since: at(12, 48))
        let now = at(13, 30)
        let verdict = VerdictBuilder.build(
            ramps: ramps,
            tide: tide(direction: "Falling",
                       predictions: [TidePrediction(time: at(16, 57), type: "L", height: -0.1)]),
            sunset: at(19, 11),
            now: now
        )
        #expect(verdict.category == .closed)
        #expect(verdict.headline == "Crawford Rd closed")
        // reopen = next low (4:57 PM) + 90 min = 6:27 PM
        #expect(verdict.subline == "Four open · closed for high tide since 12:48 PM · reopens near 6:27 PM")
    }

    // MARK: README scenario: Beachway closing soon

    @Test func entranceOnlyRisingTideScenario() {
        var ramps = allOpen()
        ramps[0] = ramp("BEACHWAY AV", "OPEN - ENTRANCE ONLY", since: at(11, 15))
        let verdict = VerdictBuilder.build(
            ramps: ramps,
            tide: tide(direction: "Rising",
                       predictions: [TidePrediction(time: at(16, 57), type: "H", height: 2.8)]),
            sunset: at(20, 4),
            now: at(13, 30)
        )
        #expect(verdict.category == .limited)
        #expect(verdict.headline == "Beachway Av closing soon")
        #expect(verdict.subline == "High tide 4:57 PM · entrance only since 11:15 AM · four others fully open")
    }

    @Test func entranceOnlyFallingTideIsNotClosingSoon() {
        var ramps = allOpen()
        ramps[0] = ramp("BEACHWAY AV", "OPEN - ENTRANCE ONLY", since: at(11, 15))
        let verdict = VerdictBuilder.build(
            ramps: ramps,
            tide: tide(direction: "Falling",
                       predictions: [TidePrediction(time: at(16, 57), type: "L", height: -0.1)]),
            sunset: at(20, 4),
            now: at(13, 30)
        )
        #expect(verdict.headline == "Beachway Av entrance only")
    }

    // MARK: README scenario: Stale data

    @Test func staleScenario() {
        let verdict = VerdictBuilder.build(
            ramps: allOpen(),
            tide: nil,
            sunset: at(20, 4),
            now: at(13, 30),
            dataAge: 14 * 60
        )
        #expect(verdict.category == .limited)
        #expect(verdict.headline == "Last known: five open")
        #expect(verdict.subline == "County feed unreachable for 14 minutes · retrying every 60s · do not trust this board")
    }

    @Test func staleWithExceptionNamesIt() {
        var ramps = allOpen()
        ramps[1] = ramp("CRAWFORD RD", "CLOSED FOR HIGH TIDE", since: at(12, 48))
        let verdict = VerdictBuilder.build(
            ramps: ramps, tide: nil, sunset: nil, now: at(13, 30), dataAge: 300
        )
        #expect(verdict.headline == "Last known: Crawford Rd closed")
    }

    @Test func freshDataAgeIsNotStale() {
        let verdict = VerdictBuilder.build(
            ramps: allOpen(), tide: nil, sunset: nil, now: at(13, 30), dataAge: 90
        )
        #expect(verdict.headline == "All five open")
    }

    // MARK: Multiple exceptions

    @Test func twoClosedNamesBoth() {
        var ramps = allOpen()
        ramps[1] = ramp("CRAWFORD RD", "CLOSED", since: at(12, 48))
        ramps[2] = ramp("FLAGLER AV", "CLOSED", since: at(12, 50))
        let verdict = VerdictBuilder.build(ramps: ramps, tide: nil, sunset: nil, now: at(13, 30))
        #expect(verdict.headline == "Crawford Rd & Flagler Av closed")
        #expect(verdict.subline == "Three open")
    }

    @Test func threeClosedUsesSpelledCount() {
        var ramps = allOpen()
        for i in 1...3 {
            ramps[i] = ramp(ramps[i].rampName, "CLOSED", since: at(12, 48))
        }
        let verdict = VerdictBuilder.build(ramps: ramps, tide: nil, sunset: nil, now: at(13, 30))
        #expect(verdict.headline == "Three ramps closed")
    }

    @Test func allClosed() {
        let ramps = allOpen().map { ramp($0.rampName, "CLOSED", since: at(12, 48)) }
        let verdict = VerdictBuilder.build(ramps: ramps, tide: nil, sunset: nil, now: at(13, 30))
        #expect(verdict.headline == "All five closed")
        #expect(verdict.subline == "none open")
    }

    @Test func closedOutranksLimited() {
        var ramps = allOpen()
        ramps[0] = ramp("BEACHWAY AV", "OPEN - ENTRANCE ONLY", since: at(11, 15))
        ramps[1] = ramp("CRAWFORD RD", "CLOSED FOR HIGH TIDE", since: at(12, 48))
        let verdict = VerdictBuilder.build(ramps: ramps, tide: nil, sunset: nil, now: at(13, 30))
        #expect(verdict.category == .closed)
        #expect(verdict.headline == "Crawford Rd closed")
        #expect(verdict.subline.hasPrefix("Three open · one limited"))
    }

    // MARK: Edge cases

    @Test func emptyRampsWaitsForFeed() {
        let verdict = VerdictBuilder.build(ramps: [], tide: nil, sunset: nil, now: at(13, 30))
        #expect(verdict.headline == "Waiting for county feed")
        #expect(verdict.category == .limited)
    }

    @Test func noTideOrSunStillReadable() {
        let verdict = VerdictBuilder.build(ramps: allOpen(), tide: nil, sunset: nil, now: at(13, 30))
        #expect(verdict.headline == "All five open")
        #expect(verdict.subline.isEmpty)
    }

    @Test func afterSunsetOmitsLightLeft() {
        let verdict = VerdictBuilder.build(
            ramps: allOpen(),
            tide: nil,
            sunset: at(20, 4),
            now: at(21, 0)
        )
        #expect(!verdict.subline.contains("light left"))
    }

    @Test func reopenEstimateInPastIsOmitted() {
        var ramps = allOpen()
        ramps[1] = ramp("CRAWFORD RD", "CLOSED FOR HIGH TIDE", since: at(4, 0))
        let verdict = VerdictBuilder.build(
            ramps: ramps,
            tide: tide(direction: "Falling",
                       predictions: [TidePrediction(time: at(5, 0), type: "L", height: -0.1)]),
            sunset: nil,
            now: at(13, 30)
        )
        #expect(!verdict.subline.contains("reopens"))
    }

    @Test func fourByFourOnlyPhrasing() {
        var ramps = allOpen()
        ramps[3] = ramp("3RD AV", "4X4 ONLY", since: at(9, 0))
        let verdict = VerdictBuilder.build(ramps: ramps, tide: nil, sunset: nil, now: at(13, 30))
        #expect(verdict.headline == "3rd Av 4x4 only")
    }
}
