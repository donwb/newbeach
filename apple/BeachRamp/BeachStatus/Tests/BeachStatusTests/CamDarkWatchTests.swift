import XCTest
@testable import BeachStatus

final class CamDarkWatchTests: XCTestCase {
    /// Noon and 2am Eastern, 2026-10-09.
    private let noon = Date(timeIntervalSince1970: 1_791_561_600)
    private let night = Date(timeIntervalSince1970: 1_791_525_600)

    private func cam(_ id: String, online: Bool? = true, url: String? = nil) -> Camera {
        Camera(id: id, name: id, location: id,
               streamURL: url ?? "https://cams.donwb.com/\(id)/index.m3u8", online: online)
    }

    private var roster: [Camera] {
        [cam("nsb"), cam("ponce-inlet"), cam("dunlawton"), cam("ormond-beach")]
    }

    /// Feeds black samples every 2s from `start` until the watch names a cam
    /// or `limit` seconds pass. Returns the switch and the seconds it took.
    private func runDark(_ watch: inout CamDarkWatch, on current: String,
                         roster: [Camera], from start: Date,
                         limit: TimeInterval = 30) -> (String?, TimeInterval) {
        var t: TimeInterval = 0
        while t <= limit {
            if let next = watch.note(lit: false, watching: current, roster: roster,
                                     at: start.addingTimeInterval(t)) {
                return (next, t)
            }
            t += 2
        }
        return (nil, t)
    }

    func testSwitchesToNextCamAfterTenSecondsOfBlack() {
        var watch = CamDarkWatch()
        let (next, after) = runDark(&watch, on: "nsb", roster: roster, from: noon)
        XCTAssertEqual(next, "ponce-inlet")
        XCTAssertEqual(after, 10)
    }

    func testLitPictureResetsTheClock() {
        var watch = CamDarkWatch()
        XCTAssertNil(watch.note(lit: false, watching: "nsb", roster: roster, at: noon))
        XCTAssertNil(watch.note(lit: false, watching: "nsb", roster: roster,
                                at: noon.addingTimeInterval(8)))
        XCTAssertNil(watch.note(lit: true, watching: "nsb", roster: roster,
                                at: noon.addingTimeInterval(9)))
        XCTAssertNil(watch.note(lit: false, watching: "nsb", roster: roster,
                                at: noon.addingTimeInterval(12)))
        XCTAssertNil(watch.note(lit: false, watching: "nsb", roster: roster,
                                at: noon.addingTimeInterval(20)))
    }

    func testWrapsAndSkipsOfflineCams() {
        let roster = [cam("nsb"), cam("ponce-inlet", online: false), cam("dunlawton")]
        var watch = CamDarkWatch()
        XCTAssertEqual(runDark(&watch, on: "dunlawton", roster: roster, from: noon).0, "nsb")
        // nsb black too: ponce is offline and dunlawton was already left
        // black this sweep, so it stays put.
        watch.restart()
        XCTAssertNil(runDark(&watch, on: "nsb", roster: roster, from: noon.addingTimeInterval(60)).0)
    }

    func testUnobservedHealthStillCounts() {
        let roster = [cam("nsb"), cam("ponce-inlet", online: nil)]
        var watch = CamDarkWatch()
        XCTAssertEqual(runDark(&watch, on: "nsb", roster: roster, from: noon).0, "ponce-inlet")
    }

    func testSweepStopsWhenEveryCamIsBlackThenRests() {
        var watch = CamDarkWatch()
        var current = "nsb"
        var clock = noon
        var visited = [current]
        while let next = runDarkStep(&watch, on: current, from: &clock) {
            current = next
            visited.append(next)
            watch.restart()
        }
        // One pass over the roster, then it stays put.
        XCTAssertEqual(visited, ["nsb", "ponce-inlet", "dunlawton", "ormond-beach"])
        // Resting: no switching for a while, then a fresh sweep.
        let (during, _) = runDark(&watch, on: current, roster: roster, from: clock, limit: 60)
        XCTAssertNil(during)
        let (after, _) = runDark(&watch, on: current, roster: roster,
                                 from: clock.addingTimeInterval(CamDarkWatch.restAfterSweep))
        XCTAssertEqual(after, "nsb")
    }

    private func runDarkStep(_ watch: inout CamDarkWatch, on current: String,
                             from clock: inout Date) -> String? {
        let (next, after) = runDark(&watch, on: current, roster: roster, from: clock)
        clock = clock.addingTimeInterval(after + 2)
        return next
    }

    func testLitPictureEndsTheSweep() {
        var watch = CamDarkWatch()
        XCTAssertEqual(runDark(&watch, on: "nsb", roster: roster, from: noon).0, "ponce-inlet")
        watch.restart()
        _ = watch.note(lit: true, watching: "ponce-inlet", roster: roster,
                       at: noon.addingTimeInterval(20))
        // Ponce goes black later: nsb is a candidate again.
        XCTAssertEqual(runDark(&watch, on: "ponce-inlet",
                               roster: [cam("nsb"), cam("ponce-inlet")],
                               from: noon.addingTimeInterval(300)).0, "nsb")
    }

    func testStandsDownAtNight() {
        var watch = CamDarkWatch()
        XCTAssertNil(runDark(&watch, on: "nsb", roster: roster, from: night, limit: 120).0)
    }

    func testBlackFrameReading() {
        let black = [UInt8](repeating: 0, count: 1000)
        XCTAssertTrue(CamPicture.isBlack(luma: black, videoRange: false))
        // Video-range black sits at 16.
        XCTAssertTrue(CamPicture.isBlack(luma: [UInt8](repeating: 16, count: 1000), videoRange: true))
        // A dead feed with a small burned-in overlay still reads black.
        var overlay = black
        for i in 0..<20 { overlay[i] = 230 }
        XCTAssertTrue(CamPicture.isBlack(luma: overlay, videoRange: false))
        // A daytime frame (2026-10-09 samples: mean ~130, min ~80).
        let day = (0..<1000).map { UInt8(80 + $0 % 100) }
        XCTAssertFalse(CamPicture.isBlack(luma: day, videoRange: false))
        // A dim scene with a lit tenth of the frame is a picture.
        var dim = [UInt8](repeating: 10, count: 1000)
        for i in 0..<100 { dim[i] = 120 }
        XCTAssertFalse(CamPicture.isBlack(luma: dim, videoRange: false))
        XCTAssertFalse(CamPicture.isBlack(luma: [], videoRange: false))
    }
}
