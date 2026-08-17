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

    /// The glanceable board hint for a ramp: boards always look forward, so
    /// a tide-closed ramp shows its reopen estimate ("often back open around
    /// 5pm") rather than a since time, a flagged drivable ramp shows its
    /// closure hint, and everything else shows nothing. Non-tide closures
    /// (turtles, capacity) have no prediction and return nil.
    public func boardHint(forAccessID accessID: String, category: StatusCategory) -> String? {
        guard let entry = ramp(for: accessID) else { return nil }
        if entry.risk == "closed_now" {
            return entry.reopen?.label
        }
        guard category != .closed, entry.flagsRisk else { return nil }
        return entry.short
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
    /// "none", "possible", "likely", "scheduled", or "closed_now". Kept as
    /// a raw string so new server values degrade gracefully; use `flagsRisk`
    /// for the "worth showing a hint" check. none/possible/likely grade the
    /// tide only; "scheduled" means the closure coming is the driving day
    /// ending, which is not in doubt.
    public let risk: String
    /// Why the predicted closure is coming: "high_tide" or "end_of_day".
    /// Optional — older servers omit it. The copy already names the reason;
    /// this is for clients that want to branch on it (icon, color).
    public let reason: String?
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

    public init(risk: String, reason: String? = nil, accessID: String, rampID: Int,
                confidence: String, headline: String, detail: String?, short: String?,
                window: OutlookWindow?, reopen: OutlookReopen?) {
        self.risk = risk
        self.reason = reason
        self.accessID = accessID
        self.rampID = rampID
        self.confidence = confidence
        self.headline = headline
        self.detail = detail
        self.short = short
        self.window = window
        self.reopen = reopen
    }

    /// Whether the server predicts a closure worth hinting at: a tide
    /// closure ("possible"/"likely") or the driving day ending
    /// ("scheduled"). False for "none" and for factual "closed_now" states,
    /// where the reopen label tells the story instead.
    public var flagsRisk: Bool {
        risk == "possible" || risk == "likely" || risk == "scheduled"
    }

    enum CodingKeys: String, CodingKey {
        case risk
        case reason
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
