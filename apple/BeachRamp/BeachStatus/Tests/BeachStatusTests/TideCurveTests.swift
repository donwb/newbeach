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
}
