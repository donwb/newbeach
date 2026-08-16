import Foundation

/// The server's beach open/close prediction from `/api/v2/outlook`: a
/// driving-hours schedule for the day plus a per-ramp tide-closure outlook.
/// Every human-readable string is server-built — clients render them
/// verbatim and never compute their own predictions, so all platforms tell
/// the same story (see CLAUDE.md "Prediction").
public struct Outlook: Codable, Sendable {
    public let generatedAt: Date
    /// "turtle" (May–Oct fixed hours) or "standard" (sunrise to sunset).
    public let season: String
    public let schedule: OutlookSchedule
    public let tide: OutlookTide
    public let ramps: [RampOutlook]

    public init(generatedAt: Date, season: String, schedule: OutlookSchedule,
                tide: OutlookTide, ramps: [RampOutlook]) {
        self.generatedAt = generatedAt
        self.season = season
        self.schedule = schedule
        self.tide = tide
        self.ramps = ramps
    }

    /// The outlook for a ramp, keyed by county access id.
    public func ramp(for accessID: String) -> RampOutlook? {
        ramps.first { $0.accessID == accessID }
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case season
        case schedule
        case tide
        case ramps
    }
}

/// The day's driving-hours frame. Labels carry approximate times
/// ("sunset (~5:30pm)") in the off-season.
public struct OutlookSchedule: Codable, Sendable {
    public let opensLabel: String
    public let closesLabel: String
    public let opensAt: Date?
    public let closesAt: Date?

    public init(opensLabel: String, closesLabel: String, opensAt: Date?, closesAt: Date?) {
        self.opensLabel = opensLabel
        self.closesLabel = closesLabel
        self.opensAt = opensAt
        self.closesAt = closesAt
    }

    enum CodingKeys: String, CodingKey {
        case opensLabel = "opens_label"
        case closesLabel = "closes_label"
        case opensAt = "opens_at"
        case closesAt = "closes_at"
    }
}

/// Shared tide backdrop: the next predicted high-tide peak.
public struct OutlookTide: Codable, Sendable {
    public let nextPeakFt: Double?
    public let nextPeakAt: Date?

    public init(nextPeakFt: Double?, nextPeakAt: Date?) {
        self.nextPeakFt = nextPeakFt
        self.nextPeakAt = nextPeakAt
    }

    enum CodingKeys: String, CodingKey {
        case nextPeakFt = "next_peak_ft"
        case nextPeakAt = "next_peak_at"
    }
}

/// One ramp's tide outlook for the rest of the driving day.
public struct RampOutlook: Codable, Sendable {
    /// "none", "possible", "likely", or "closed_now". Kept as a raw string
    /// so new server values degrade gracefully; use `flagsRisk` for the
    /// "worth showing a hint" check.
    public let risk: String
    public let accessID: String
    public let rampID: Int
    /// "low", "medium", or "high" — how much history backs this ramp.
    public let confidence: String
    public let headline: String
    public let detail: String?
    /// Compact hint for tight spots ("closure likely ~1:30pm").
    public let short: String?
    public let window: OutlookWindow?
    public let reopen: OutlookReopen?

    public init(risk: String, accessID: String, rampID: Int, confidence: String,
                headline: String, detail: String?, short: String?,
                window: OutlookWindow?, reopen: OutlookReopen?) {
        self.risk = risk
        self.accessID = accessID
        self.rampID = rampID
        self.confidence = confidence
        self.headline = headline
        self.detail = detail
        self.short = short
        self.window = window
        self.reopen = reopen
    }

    /// Whether the server predicts a closure worth hinting at ("possible"
    /// or "likely"). False for "none" and for factual "closed_now" states,
    /// where the ramp's own status already tells the story.
    public var flagsRisk: Bool {
        risk == "possible" || risk == "likely"
    }

    enum CodingKeys: String, CodingKey {
        case risk
        case accessID = "access_id"
        case rampID = "ramp_id"
        case confidence
        case headline
        case detail
        case short
        case window
        case reopen
    }
}

/// A coarse predicted closure window, pre-rounded server-side.
public struct OutlookWindow: Codable, Sendable {
    public let label: String
    public let start: Date
    public let end: Date

    public init(label: String, start: Date, end: Date) {
        self.label = label
        self.start = start
        self.end = end
    }
}

/// A reopen estimate — a casual label only, never a promise.
public struct OutlookReopen: Codable, Sendable {
    public let label: String

    public init(label: String) {
        self.label = label
    }
}
