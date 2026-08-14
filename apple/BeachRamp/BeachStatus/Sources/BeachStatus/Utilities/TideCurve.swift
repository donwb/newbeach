import Foundation

/// Cosine-interpolated tide curve between NOAA high/low extremes:
///
///     h(t) = h₀ + (h₁ − h₀) · (1 − cos(π·u)) / 2,   u = (t − t₀)/(t₁ − t₀)
///
/// NOAA's day extremes don't cover midnight-to-first-extreme, so the curve
/// extends past both ends with reflected phantom extremes (same spacing as
/// the nearest real pair, height copied from the opposite-type neighbor).
public enum TideCurve {
    public struct Point: Equatable, Sendable {
        public let time: Date
        public let height: Double

        public init(time: Date, height: Double) {
            self.time = time
            self.height = height
        }
    }

    /// Samples the curve every `stepMinutes` across `range`. Extremes without
    /// heights are ignored; fewer than two usable extremes yields [].
    public static func points(extremes: [TidePrediction],
                              in range: ClosedRange<Date>,
                              stepMinutes: Int = 10) -> [Point] {
        var anchors: [Point] = extremes.compactMap { p in
            guard let h = p.height else { return nil }
            return Point(time: p.time, height: h)
        }.sorted { $0.time < $1.time }

        guard anchors.count >= 2, stepMinutes > 0 else { return [] }

        // Reflect the first/last pair outward so the curve covers the whole
        // range even before the day's first extreme and after its last.
        while anchors[0].time > range.lowerBound {
            let spacing = anchors[1].time.timeIntervalSince(anchors[0].time)
            guard spacing > 0 else { break }
            anchors.insert(Point(time: anchors[0].time.addingTimeInterval(-spacing),
                                 height: anchors[1].height), at: 0)
        }
        while anchors[anchors.count - 1].time < range.upperBound {
            let last = anchors[anchors.count - 1]
            let spacing = last.time.timeIntervalSince(anchors[anchors.count - 2].time)
            guard spacing > 0 else { break }
            anchors.append(Point(time: last.time.addingTimeInterval(spacing),
                                 height: anchors[anchors.count - 2].height))
        }

        let step = TimeInterval(stepMinutes * 60)
        var points: [Point] = []
        var t = range.lowerBound
        while t <= range.upperBound {
            if let h = height(at: t, anchors: anchors) {
                points.append(Point(time: t, height: h))
            }
            t = t.addingTimeInterval(step)
        }
        return points
    }

    /// Height at a single moment, interpolated between the bracketing anchors.
    static func height(at time: Date, anchors: [Point]) -> Double? {
        guard let first = anchors.first, let last = anchors.last else { return nil }
        if time <= first.time { return first.height }
        if time >= last.time { return last.height }

        for i in 1..<anchors.count where time <= anchors[i].time {
            let a = anchors[i - 1], b = anchors[i]
            let span = b.time.timeIntervalSince(a.time)
            guard span > 0 else { return a.height }
            let u = time.timeIntervalSince(a.time) / span
            return a.height + (b.height - a.height) * (1 - cos(.pi * u)) / 2
        }
        return last.height
    }
}
