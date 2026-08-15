import Foundation

/// A forward-looking projection for one ramp against its closure threshold.
public struct ClosureProjection: Equatable, Sendable {
    public enum Kind: Sendable {
        /// The tide will rise past the ramp's threshold.
        case closure
        /// The ramp is closed and the tide will drop back below the threshold.
        case reopen
    }

    public let kind: Kind
    /// When the tide crosses the threshold.
    public let time: Date
    /// The handoff's forward-looking line, e.g.
    /// "Expect full closure near high tide 11:07 PM." /
    /// "Reopens near 6:30 PM as the tide drops."
    public let line: String
}

/// Turns a tide curve plus a ramp's closure height into the line the detail
/// screen exists for. Everything is nil when the ramp has no threshold —
/// callers hide the line rather than invent one.
public enum ClosureProjector {
    /// How far ahead a projection is worth stating. Beyond the chart's data
    /// there is nothing to interpolate anyway.
    public static func project(
        ramp: Ramp,
        hourly: [HourlyTidePoint],
        highLow: [TidePrediction]? = nil,
        now: Date = Date(),
        timeZone: TimeZone = SinceFormatter.eastern
    ) -> ClosureProjection? {
        guard let threshold = ramp.closureHeightFt else { return nil }
        let points = hourly.sorted { $0.time < $1.time }
        guard points.count >= 2 else { return nil }

        if ramp.category == .closed {
            guard let crossing = crossing(points, threshold: threshold, rising: false, after: now)
            else { return nil }
            let clock = SinceFormatter.clock(crossing, timeZone: timeZone)
            return ClosureProjection(
                kind: .reopen,
                time: crossing,
                line: "Reopens near \(clock) as the tide drops."
            )
        }

        guard let crossing = crossing(points, threshold: threshold, rising: true, after: now)
        else { return nil }

        // The county closes around the high, so name the high when it is the
        // event the crossing is riding toward.
        if let high = highLow?
            .filter({ $0.type == "H" && $0.time >= crossing && ($0.height ?? .infinity) >= threshold })
            .min(by: { $0.time < $1.time }) {
            return ClosureProjection(
                kind: .closure,
                time: crossing,
                line: "Expect full closure near high tide \(SinceFormatter.clock(high.time, timeZone: timeZone))."
            )
        }
        return ClosureProjection(
            kind: .closure,
            time: crossing,
            line: "Expect full closure near \(SinceFormatter.clock(crossing, timeZone: timeZone))."
        )
    }

    /// First time after `after` where the curve crosses `threshold` in the
    /// given direction, linearly interpolated between hourly points.
    static func crossing(
        _ points: [HourlyTidePoint],
        threshold: Double,
        rising: Bool,
        after: Date
    ) -> Date? {
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            guard b.time > after else { continue }
            let crosses = rising
                ? (a.height < threshold && b.height >= threshold)
                : (a.height >= threshold && b.height < threshold)
            guard crosses, b.height != a.height else { continue }
            let t = (threshold - a.height) / (b.height - a.height)
            let interval = b.time.timeIntervalSince(a.time)
            let when = a.time.addingTimeInterval(interval * t)
            if when > after { return when }
        }
        return nil
    }
}
