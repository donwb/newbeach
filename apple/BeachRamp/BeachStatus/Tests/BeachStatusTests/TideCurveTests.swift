import Foundation
import Testing
@testable import BeachStatus

struct TideCurveTests {
    private static let eastern = TimeZone(identifier: "America/New_York")!

    private func at(_ hour: Int, _ minute: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: Self.eastern,
            year: 2026, month: 8, day: 14, hour: hour, minute: minute
        ).date!
    }

    private var extremes: [TidePrediction] {
        [
            TidePrediction(time: at(4, 40), type: "L", height: -0.1),
            TidePrediction(time: at(10, 44), type: "H", height: 2.8),
            TidePrediction(time: at(16, 57), type: "L", height: -0.1),
            TidePrediction(time: at(23, 7), type: "H", height: 2.8),
        ]
    }

    @Test func hitsExtremeValuesExactly() {
        let anchors = extremes.map { TideCurve.Point(time: $0.time, height: $0.height!) }
        #expect(TideCurve.height(at: at(4, 40), anchors: anchors) == -0.1)
        #expect(TideCurve.height(at: at(10, 44), anchors: anchors) == 2.8)
    }

    @Test func midpointIsAverageOfNeighbors() throws {
        let anchors = extremes.map { TideCurve.Point(time: $0.time, height: $0.height!) }
        // Cosine easing passes through the arithmetic mean at u = 0.5.
        let mid = at(4, 40).addingTimeInterval(at(10, 44).timeIntervalSince(at(4, 40)) / 2)
        let h = try #require(TideCurve.height(at: mid, anchors: anchors))
        #expect(abs(h - 1.35) < 0.0001)
    }

    @Test func coversFullDayViaPhantomExtremes() throws {
        let start = at(0, 0)
        let end = at(23, 50)
        let points = TideCurve.points(extremes: extremes, in: start...end)
        let first = try #require(points.first)
        let last = try #require(points.last)
        #expect(first.time == start)
        #expect(last.time >= at(23, 40))
        // Midnight sits on the falling limb from a phantom pre-dawn high;
        // it must be a real interpolated value, not a flat clamp.
        #expect(first.height > -0.1 && first.height < 2.8)
    }

    @Test func tenMinuteSampling() {
        let points = TideCurve.points(extremes: extremes, in: at(6, 0)...at(7, 0))
        #expect(points.count == 7)
        #expect(points[1].time.timeIntervalSince(points[0].time) == 600)
    }

    @Test func extremesWithoutHeightsYieldEmpty() {
        let bare = [
            TidePrediction(time: at(4, 40), type: "L"),
            TidePrediction(time: at(10, 44), type: "H"),
        ]
        #expect(TideCurve.points(extremes: bare, in: at(0, 0)...at(23, 59)).isEmpty)
    }

    @Test func monotonicRiseBetweenLowAndHigh() {
        let points = TideCurve.points(extremes: extremes, in: at(4, 40)...at(10, 44))
        let heights = points.map(\.height)
        #expect(heights == heights.sorted())
    }

    @Test func tomorrowOverlaySharesTodaysAxis() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.eastern
        let start = at(0, 0)
        let range = start...cal.date(byAdding: .day, value: 1, to: start)!
        let tomorrow = [
            TidePrediction(time: at(5, 30).addingTimeInterval(86_400), type: "L", height: 0.2),
            TidePrediction(time: at(11, 34).addingTimeInterval(86_400), type: "H", height: 3.1),
            TidePrediction(time: at(17, 47).addingTimeInterval(86_400), type: "L", height: 0.2),
        ]
        let overlay = TideCurve.tomorrowOverlay(today: extremes, tomorrow: tomorrow,
                                                in: range, calendar: cal)
        let first = try #require(overlay.first)
        let last = try #require(overlay.last)
        #expect(first.time == range.lowerBound)
        #expect(last.time == range.upperBound)
        // Tomorrow's 11:34 high lands at today's 11:34 on the shared axis.
        // (Daytime only: the reflected phantom past tomorrow's last low
        // repeats the 3.1 at midnight.)
        let peak = try #require(overlay.filter { $0.time < at(18, 0) }
            .max { $0.height < $1.height })
        #expect(abs(peak.time.timeIntervalSince(at(11, 34))) <= 10 * 60)
        #expect(abs(peak.height - 3.1) < 0.05)
        // The join at midnight follows today's 11:07pm high, not a phantom.
        #expect(first.height > 2.5)
    }

    @Test func tomorrowOverlayEmptyWithoutData() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.eastern
        let range = at(0, 0)...at(23, 59)
        #expect(TideCurve.tomorrowOverlay(today: extremes, tomorrow: [],
                                          in: range, calendar: cal).isEmpty)
    }
}
