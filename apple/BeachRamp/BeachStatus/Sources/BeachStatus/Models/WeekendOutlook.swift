import Foundation

/// The server's "when should I go this weekend?" answer from
/// `/api/v2/outlook/weekend`: the next six days, each graded with a verdict
/// and casual copy. Like `Outlook`, every human-readable string is
/// server-built and rendered verbatim — clients never compute their own
/// predictions. The verdict vocabulary (`great|good|mixed|tough|no_call`) is
/// deliberately separate from `RampOutlook.risk` and must never borrow it.
public struct WeekendOutlook: Codable, Sendable {
    public let generatedAt: Date
    /// The week's one-line summary ("Saturday's the day this weekend…").
    public let headline: String
    /// Six days, today first, Eastern calendar.
    public let days: [WeekendDay]

    public init(generatedAt: Date, headline: String, days: [WeekendDay]) {
        self.generatedAt = generatedAt
        self.headline = headline
        self.days = days
    }

    /// The graded weekend days (Saturday/Sunday) still in the horizon —
    /// what a compact surface (a stat tile) leads with.
    public var weekendDays: [WeekendDay] {
        days.filter(\.isWeekend)
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case headline
        case days
    }
}

/// One graded day of the weekend outlook.
public struct WeekendDay: Codable, Sendable {
    /// Eastern calendar date, "2026-08-22". A plain string on purpose — it is
    /// a date label, not an instant.
    public let date: String
    public let weekday: String
    public let isWeekend: Bool
    /// "great", "good", "mixed", "tough", or "no_call". Kept as a raw string
    /// so new server values degrade gracefully.
    public let verdict: String
    /// What bound the grade ("tide", "storms", "wind", "heat", "cold").
    public let drivers: [String]?
    /// What the grade could see: "tide" always, plus "weather"/"marine" when
    /// NWS coverage was available. A tide-only basis means an honest but
    /// weather-blind verdict.
    public let basis: [String]
    public let headline: String
    /// Pill justification, present only when the headline doesn't carry it.
    public let why: String?
    public let detail: String?
    public let bestWindow: OutlookWindow?
    /// "none", "some", or "high" — how hard the tide leans on the ramps.
    public let closurePressure: String
    public let schedule: OutlookSchedule?
    public let highTempF: Double?
    /// Max heat index, sent only when it meaningfully exceeds the air temp.
    public let feelsLikeF: Double?
    public let rainChancePct: Double?
    public let windLabel: String?

    public init(date: String, weekday: String, isWeekend: Bool, verdict: String,
                drivers: [String]? = nil, basis: [String], headline: String,
                why: String? = nil, detail: String? = nil,
                bestWindow: OutlookWindow? = nil, closurePressure: String,
                schedule: OutlookSchedule? = nil, highTempF: Double? = nil,
                feelsLikeF: Double? = nil, rainChancePct: Double? = nil,
                windLabel: String? = nil) {
        self.date = date
        self.weekday = weekday
        self.isWeekend = isWeekend
        self.verdict = verdict
        self.drivers = drivers
        self.basis = basis
        self.headline = headline
        self.why = why
        self.detail = detail
        self.bestWindow = bestWindow
        self.closurePressure = closurePressure
        self.schedule = schedule
        self.highTempF = highTempF
        self.feelsLikeF = feelsLikeF
        self.rainChancePct = rainChancePct
        self.windLabel = windLabel
    }

    /// "Sat" — the three-letter weekday for tight spots, matching the web.
    public var weekdayShort: String {
        String(weekday.prefix(3))
    }

    /// "no_call" → "no call", ready for display casing.
    public var verdictDisplay: String {
        verdict.replacingOccurrences(of: "_", with: " ")
    }

    enum CodingKeys: String, CodingKey {
        case date
        case weekday
        case isWeekend = "is_weekend"
        case verdict
        case drivers
        case basis
        case headline
        case why
        case detail
        case bestWindow = "best_window"
        case closurePressure = "closure_pressure"
        case schedule
        case highTempF = "high_temp_f"
        case feelsLikeF = "feels_like_f"
        case rainChancePct = "rain_chance_pct"
        case windLabel = "wind_label"
    }
}
