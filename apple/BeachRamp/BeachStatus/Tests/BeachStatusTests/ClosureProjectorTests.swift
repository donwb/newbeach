import Foundation
import Testing
@testable import BeachStatus

struct ClosureProjectorTests {
    private static let eastern = TimeZone(identifier: "America/New_York")!

    private func date(_ hour: Int, _ minute: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: Self.eastern,
            year: 2026, month: 8, day: 14, hour: hour, minute: minute
        ).date!
    }

    private func ramp(category: String, closureHeightFt: Double?) -> Ramp {
        Ramp(id: 1, rampName: "BEACHWAY AV", accessStatus: category == "open" ? "OPEN" : "CLOSED - HIGH TIDE",
             statusCategory: category, objectID: 1, city: "NEW SMYRNA BEACH", accessID: "VB01",
             location: "", lastUpdated: nil, statusSince: nil,
             closureHeightFt: closureHeightFt)
    }

    /// Rising curve: 1.0 ft at 2 PM climbing 0.5 ft/h to 4.0 ft at 8 PM.
    private var risingCurve: [HourlyTidePoint] {
        (0...6).map { h in
            point(date(14 + h, 0), 1.0 + Double(h) * 0.5)
        }
    }

    /// Falling curve: 3.0 ft at 2 PM dropping 0.5 ft/h to 0 ft at 8 PM.
    private var fallingCurve: [HourlyTidePoint] {
        (0...6).map { h in
            point(date(14 + h, 0), 3.0 - Double(h) * 0.5)
        }
    }

    private func point(_ time: Date, _ height: Double) -> HourlyTidePoint {
        let json = """
        {"time": "\(ISO8601DateFormatter().string(from: time))", "height": \(height)}
        """
        return try! JSONDecoder.iso.decode(HourlyTidePoint.self, from: Data(json.utf8))
    }

    @Test func noThresholdMeansNoProjection() {
        let result = ClosureProjector.project(
            ramp: ramp(category: "open", closureHeightFt: nil),
            hourly: risingCurve, now: date(14, 30))
        #expect(result == nil)
    }

    @Test func risingTideProjectsClosureAtCrossing() {
        // Threshold 2.4 ft: curve hits it at 2:48 PM… between 4 PM (2.0) and
        // 5 PM (2.5), at t = 0.8 → 4:48 PM.
        let result = ClosureProjector.project(
            ramp: ramp(category: "open", closureHeightFt: 2.4),
            hourly: risingCurve, now: date(14, 30))
        #expect(result?.kind == .closure)
        let expected = date(16, 48)
        #expect(abs(result!.time.timeIntervalSince(expected)) < 60)
        #expect(result!.line.hasPrefix("Expect full closure near"))
    }

    @Test func closureNamesTheHighWhenItQualifies() {
        let high = TidePrediction(time: date(23, 7), type: "H", height: 3.9)
        let result = ClosureProjector.project(
            ramp: ramp(category: "open", closureHeightFt: 2.4),
            hourly: risingCurve, highLow: [high], now: date(14, 30))
        #expect(result?.line == "Expect full closure near high tide 11:07 PM.")
    }

    @Test func closedRampProjectsReopenOnFallingTide() {
        // Threshold 2.4 ft falling: between 3 PM (2.5) and 4 PM (2.0),
        // t = 0.2 → 3:12 PM.
        let result = ClosureProjector.project(
            ramp: ramp(category: "closed", closureHeightFt: 2.4),
            hourly: fallingCurve, now: date(14, 30))
        #expect(result?.kind == .reopen)
        let expected = date(15, 12)
        #expect(abs(result!.time.timeIntervalSince(expected)) < 60)
        #expect(result!.line.hasSuffix("as the tide drops."))
    }

    @Test func noCrossingMeansNoProjection() {
        // Threshold above the whole curve.
        let result = ClosureProjector.project(
            ramp: ramp(category: "open", closureHeightFt: 9.9),
            hourly: risingCurve, now: date(14, 30))
        #expect(result == nil)
    }

    @Test func crossingsBeforeNowAreIgnored() {
        // Now is 6:30 PM; the 2.4 ft rising crossing was 4:48 PM. The curve
        // never crosses again → nil.
        let result = ClosureProjector.project(
            ramp: ramp(category: "open", closureHeightFt: 2.4),
            hourly: risingCurve, now: date(18, 30))
        #expect(result == nil)
    }
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
