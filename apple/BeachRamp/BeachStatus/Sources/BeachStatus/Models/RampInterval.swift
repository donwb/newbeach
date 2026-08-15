import Foundation

/// Response of `/api/v2/ramps/:id/intervals` — contiguous status spans over a
/// window, oldest first. Backs the detail screen's today band.
public struct RampIntervals: Codable, Sendable {
    public let ramp: Ramp
    public let windowStart: Date
    public let windowEnd: Date
    public let intervals: [RampInterval]

    enum CodingKeys: String, CodingKey {
        case ramp
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case intervals
    }

    public init(ramp: Ramp, windowStart: Date, windowEnd: Date, intervals: [RampInterval]) {
        self.ramp = ramp
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.intervals = intervals
    }
}

/// One contiguous span of a single status.
public struct RampInterval: Codable, Sendable, Equatable {
    /// Raw county status string ("OPEN", "CLOSED - HIGH TIDE", …).
    public let status: String
    /// Normalized category string as the server sends it.
    public let category: String
    public let start: Date
    public let end: Date

    public init(status: String, category: String, start: Date, end: Date) {
        self.status = status
        self.category = category
        self.start = start
        self.end = end
    }

    public var statusCategory: StatusCategory {
        StatusCategory(rawValue: category) ?? StatusCategory(accessStatus: status)
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}
