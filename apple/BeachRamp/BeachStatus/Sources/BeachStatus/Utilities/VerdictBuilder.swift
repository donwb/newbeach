import Foundation

/// The board's one-line answer to "can I get on the beach right now?".
public struct Verdict: Equatable, Sendable {
    /// Drives the accent color: open = green, limited = amber, closed = red.
    /// Stale boards use `.limited` (amber) regardless of ramp states.
    public let category: StatusCategory
    public let headline: String
    public let subline: String

    public init(category: StatusCategory, headline: String, subline: String) {
        self.category = category
        self.headline = headline
        self.subline = subline
    }
}

/// Generates verdict copy from ramp, tide, and sun facts.
///
/// The copy rule: name the exception if there is one, otherwise state the
/// count. Never lead with a bare numeral — counts are spelled out.
public enum VerdictBuilder {
    /// Data older than this is stale: two missed 60-second refresh cycles
    /// plus jitter.
    public static let staleThreshold: TimeInterval = 150

    /// High-tide closures reopen roughly this long after the following low
    /// tide (county practice, not physics — tuned to observed reopenings).
    public static let reopenOffsetAfterLow: TimeInterval = 90 * 60

    public static func build(ramps: [Ramp],
                             tide: TideInfo?,
                             sunset: Date?,
                             now: Date = Date(),
                             dataAge: TimeInterval? = nil,
                             timeZone: TimeZone = SinceFormatter.eastern) -> Verdict {
        guard !ramps.isEmpty else {
            return Verdict(category: .limited,
                           headline: "Waiting for county feed",
                           subline: "No ramp data yet · retrying every 60s")
        }

        if let dataAge, dataAge > staleThreshold {
            return staleVerdict(ramps: ramps, dataAge: dataAge, now: now, timeZone: timeZone)
        }

        let closed = ramps.filter { $0.category == .closed }
        let limited = ramps.filter { $0.category == .limited }
        let open = ramps.filter { $0.category == .open }

        if !closed.isEmpty {
            return closedVerdict(closed: closed, limited: limited, open: open,
                                 total: ramps.count, tide: tide, now: now, timeZone: timeZone)
        }
        if !limited.isEmpty {
            return limitedVerdict(limited: limited, open: open,
                                  tide: tide, now: now, timeZone: timeZone)
        }
        return allOpenVerdict(count: ramps.count, tide: tide, sunset: sunset,
                              now: now, timeZone: timeZone)
    }

    // MARK: - Scenarios

    private static func allOpenVerdict(count: Int, tide: TideInfo?, sunset: Date?,
                                       now: Date, timeZone: TimeZone) -> Verdict {
        var parts: [String] = []
        if let tide {
            parts.append("Tide \(tide.isRising ? "rising" : "dropping")")
            if let next = nextExtreme(in: tide, after: now) {
                parts.append("\(next.label.lowercased()) \(SinceFormatter.clock(next.time, timeZone: timeZone))")
            }
        }
        if let sunset, sunset > now {
            parts.append("\(durationText(sunset.timeIntervalSince(now))) of light left")
        }
        return Verdict(category: .open,
                       headline: "All \(spelled(count)) open",
                       subline: parts.joined(separator: " · "))
    }

    private static func closedVerdict(closed: [Ramp], limited: [Ramp], open: [Ramp],
                                      total: Int, tide: TideInfo?,
                                      now: Date, timeZone: TimeZone) -> Verdict {
        let headline: String
        switch closed.count {
        case 1:
            headline = "\(closed[0].rampDisplayName) closed"
        case 2:
            headline = "\(closed[0].rampDisplayName) & \(closed[1].rampDisplayName) closed"
        case total:
            headline = "All \(spelled(total)) closed"
        default:
            headline = "\(spelled(closed.count).capitalizedFirst) ramps closed"
        }

        var parts: [String] = []
        if !open.isEmpty {
            parts.append("\(spelled(open.count).capitalizedFirst) open")
        }
        if !limited.isEmpty {
            parts.append("\(spelled(limited.count)) limited")
        }
        if closed.count == 1 {
            let ramp = closed[0]
            var segment = statusPhrase(ramp.accessStatus)
            if let since = ramp.statusSince {
                segment += " since \(SinceFormatter.string(from: since, now: now, timeZone: timeZone))"
            }
            parts.append(segment)
            if let reopen = reopenEstimate(for: ramp, tide: tide, now: now) {
                parts.append("reopens near \(SinceFormatter.clock(reopen, timeZone: timeZone))")
            }
        }
        if parts.isEmpty {
            parts.append("none open")
        }
        return Verdict(category: .closed, headline: headline,
                       subline: parts.joined(separator: " · "))
    }

    private static func limitedVerdict(limited: [Ramp], open: [Ramp],
                                       tide: TideInfo?, now: Date,
                                       timeZone: TimeZone) -> Verdict {
        let headline: String
        if limited.count == 1 {
            headline = "\(limited[0].rampDisplayName) \(limitedHeadlinePhrase(limited[0], tide: tide))"
        } else if limited.count == 2 {
            headline = "\(limited[0].rampDisplayName) & \(limited[1].rampDisplayName) limited"
        } else {
            headline = "\(spelled(limited.count).capitalizedFirst) ramps limited"
        }

        var parts: [String] = []
        if let tide, let next = nextExtreme(in: tide, after: now) {
            parts.append("\(next.label) tide \(SinceFormatter.clock(next.time, timeZone: timeZone))")
        }
        if limited.count == 1 {
            let ramp = limited[0]
            var segment = statusPhrase(ramp.accessStatus)
            if let since = ramp.statusSince {
                segment += " since \(SinceFormatter.string(from: since, now: now, timeZone: timeZone))"
            }
            parts.append(segment)
        }
        if !open.isEmpty {
            parts.append("\(spelled(open.count)) other\(open.count == 1 ? "" : "s") fully open")
        }
        return Verdict(category: .limited, headline: headline,
                       subline: parts.joined(separator: " · "))
    }

    private static func staleVerdict(ramps: [Ramp], dataAge: TimeInterval,
                                     now: Date, timeZone: TimeZone) -> Verdict {
        let closed = ramps.filter { $0.category == .closed }
        let limited = ramps.filter { $0.category == .limited }

        let summary: String
        if closed.count == 1 {
            summary = "\(closed[0].rampDisplayName) closed"
        } else if closed.count > 1 {
            summary = "\(spelled(closed.count)) closed"
        } else if limited.count == 1 {
            summary = "\(limited[0].rampDisplayName) \(statusPhrase(limited[0].accessStatus))"
        } else if limited.count > 1 {
            summary = "\(spelled(limited.count)) limited"
        } else {
            summary = "\(spelled(ramps.count)) open"
        }

        let minutes = max(1, Int((dataAge / 60).rounded()))
        return Verdict(
            category: .limited,
            headline: "Last known: \(summary)",
            subline: "County feed unreachable for \(minutes) minute\(minutes == 1 ? "" : "s") · retrying every 60s · do not trust this board"
        )
    }

    // MARK: - Phrase helpers

    /// Headline verb for a single limited ramp. Entrance-only while the tide
    /// is rising means a full closure is coming — say so.
    private static func limitedHeadlinePhrase(_ ramp: Ramp, tide: TideInfo?) -> String {
        let status = normalized(ramp.accessStatus)
        if status == "CLOSING IN PROGRESS" { return "closing now" }
        if status == "OPEN - ENTRANCE ONLY" {
            if let tide, tide.isRising { return "closing soon" }
            return "entrance only"
        }
        if status == "4X4 ONLY" { return "4x4 only" }
        return "limited"
    }

    /// Lowercase status phrase for sublines: "CLOSED FOR HIGH TIDE" →
    /// "closed for high tide", "OPEN - ENTRANCE ONLY" → "entrance only".
    static func statusPhrase(_ accessStatus: String) -> String {
        var phrase = normalized(accessStatus).lowercased()
        if phrase.hasPrefix("open - ") {
            phrase = String(phrase.dropFirst("open - ".count))
        }
        return phrase.replacingOccurrences(of: " - ", with: " — ")
    }

    private static func normalized(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespaces).uppercased()
    }

    // MARK: - Fact helpers

    /// The first tide extreme after `now`, if predictions cover it.
    public static func nextExtreme(in tide: TideInfo, after now: Date) -> TidePrediction? {
        tide.predictions?.filter { $0.time > now }.min { $0.time < $1.time }
    }

    /// Estimated reopen time for a high-tide closure: the next low tide after
    /// the closure, plus `reopenOffsetAfterLow`. Nil when it doesn't apply or
    /// the estimate is already in the past.
    static func reopenEstimate(for ramp: Ramp, tide: TideInfo?, now: Date) -> Date? {
        guard normalized(ramp.accessStatus) == "CLOSED FOR HIGH TIDE",
              let predictions = tide?.predictions else { return nil }
        let reference = ramp.statusSince ?? now
        guard let nextLow = predictions
            .filter({ $0.type == "L" && $0.time > reference })
            .min(by: { $0.time < $1.time }) else { return nil }
        let reopen = nextLow.time.addingTimeInterval(reopenOffsetAfterLow)
        return reopen > now ? reopen : nil
    }

    /// "5h 41m" / "5h" / "41m"
    public static func durationText(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    /// Spelled-out count for verdict copy: 5 → "five". Falls back to digits
    /// past twelve, where prose stops reading naturally anyway.
    static func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six",
                     "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return (0...12).contains(n) ? words[n] : String(n)
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
