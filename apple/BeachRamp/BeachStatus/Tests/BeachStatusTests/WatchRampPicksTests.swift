import XCTest
@testable import BeachStatus

final class WatchRampPicksTests: XCTestCase {
    private func ramp(_ id: String, _ name: String, city: String = "NEW SMYRNA BEACH",
                      order: Int? = nil) -> Ramp {
        Ramp(id: id.hashValue, rampName: name, accessStatus: "OPEN", statusCategory: "open",
             objectID: 0, city: city, accessID: id, location: "", lastUpdated: nil,
             sortOrder: order)
    }

    private var all: [Ramp] {
        [
            ramp("NS-141", "27TH AV", order: 5),
            ramp("NS-118", "3RD AV", order: 4),
            ramp("NS-106", "BEACHWAY AV", order: 1),
            ramp("NS-108", "CRAWFORD RD", order: 2),
            ramp("NS-110", "FLAGLER AV", order: 3),
            ramp("PI-097", "BEACH ST", city: "PONCE INLET"),
        ]
    }

    func testNoPinsTakesDriverOrder() {
        let ids = WatchRampPicks.ramps(in: "New Smyrna Beach", from: all, pinned: []).map(\.accessID)
        XCTAssertEqual(ids, ["NS-106", "NS-108", "NS-110", "NS-118"])
    }

    func testPinsComeFirstThenFillInBoardOrder() {
        let ids = WatchRampPicks.ramps(in: "New Smyrna Beach", from: all,
                                       pinned: ["NS-141", "PI-097"]).map(\.accessID)
        // 27th is pinned (in), the other city's pin is ignored, the first
        // three by driver order fill — and the card stays in board order.
        XCTAssertEqual(ids, ["NS-106", "NS-108", "NS-110", "NS-141"])
    }

    func testMorePinsThanSlotsKeepsTheOldestFour() {
        let pinned = ["NS-141", "NS-118", "NS-110", "NS-108", "NS-106"]
        let ids = WatchRampPicks.ramps(in: "New Smyrna Beach", from: all, pinned: pinned).map(\.accessID)
        XCTAssertEqual(ids, ["NS-108", "NS-110", "NS-118", "NS-141"])
    }

    func testSmallCityShowsWhatItHas() {
        let ids = WatchRampPicks.ramps(in: "Ponce Inlet", from: all, pinned: []).map(\.accessID)
        XCTAssertEqual(ids, ["PI-097"])
    }

    func testToggleRemovesAnExistingPin() {
        XCTAssertEqual(WatchRampPicks.toggling("NS-106", in: ["NS-106", "NS-108"], all: all), ["NS-108"])
    }

    func testFifthPinInACityDropsThatCitysOldest() {
        let pinned = ["PI-097", "NS-106", "NS-108", "NS-110", "NS-118"]
        let result = WatchRampPicks.toggling("NS-141", in: pinned, all: all)
        XCTAssertEqual(result, ["PI-097", "NS-108", "NS-110", "NS-118", "NS-141"])
    }
}
