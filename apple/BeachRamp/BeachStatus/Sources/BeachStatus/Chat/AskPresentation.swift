import Foundation

/// How an Ask answer is laid out in the board's voice, shared by iOS and
/// tvOS (and mirrored by `web/js/ask.js`): a kicker built from the facts,
/// the reply's first sentence as the headline, the rest as detail, then
/// only the rows that carry news — a closed ramp or one the tide could
/// close. An open ramp with nothing but the day's close is the default and
/// is not repeated. Pure, so the split and the rows are testable.
public enum AskPresentation {
    /// One line under the answer.
    public struct Row: Hashable, Sendable, Identifiable {
        public var id: String { name + state }
        public let name: String
        public let state: String
        public let note: String
        public let isClosed: Bool

        public init(name: String, state: String, note: String, isClosed: Bool) {
            self.name = name
            self.state = state
            self.note = note
            self.isClosed = isClosed
        }
    }

    /// The first sentence and the remainder. A sentence ends at `.`, `!`
    /// or `?` followed by whitespace or the end; "2.5 ft" and "6:30pm."
    /// mid-text are not breaks. A lead over 140 characters stays whole.
    public static func splitLead(_ text: String) -> (lead: String, rest: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(t)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "." || c == "!" || c == "?" {
                let atEnd = i == chars.count - 1
                let nextIsSpace = !atEnd && chars[i + 1].isWhitespace
                if atEnd || nextIsSpace {
                    let lead = String(chars[0...i])
                    if lead.count > 140 { return (t, "") }
                    let rest = atEnd ? "" : String(chars[(i + 1)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (lead, rest)
                }
            }
            i += 1
        }
        return (t, "")
    }

    /// "New Smyrna Beach · right now · 4 of 5 open", "Flagler Av · Saturday
    /// ~2pm", "The week ahead", or nil when there is nothing to anchor on.
    public static func kicker(for sources: [ChatSource]) -> String? {
        guard let s = sources.first(where: { ["city_now", "city_outlook", "ramp_outlook"].contains($0.kind) }) else {
            return sources.contains(where: { $0.kind == "weekend_day" }) ? "The week ahead" : nil
        }
        var parts: [String] = []
        if s.kind == "ramp_outlook" {
            parts = [s.name, s.atLabel].compactMap { $0 }
        } else {
            parts = [s.city, s.kind == "city_now" ? "right now" : s.atLabel].compactMap { $0 }
            if s.kind == "city_now", let open = s.openCount, let total = s.rampCount {
                parts.append("\(open) of \(total) open")
            }
        }
        let joined = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    /// The rows worth a line.
    public static func newsRows(_ sources: [ChatSource]) -> [Row] {
        var rows: [Row] = []
        for s in sources {
            switch s.kind {
            case "ramp_outlook":
                rows.append(Row(name: s.name ?? "", state: s.headline ?? "", note: s.detail ?? "", isClosed: s.isClosedNow))
            case "city_now", "city_outlook":
                for r in s.ramps ?? [] {
                    let closed = r.risk == "closed_now" || (r.status ?? "").uppercased().hasPrefix("CLOSED")
                    let risky = r.risk == "possible" || r.risk == "likely"
                    guard closed || risky else { continue }
                    let state: String
                    if s.kind == "city_now", let status = r.status, !status.isEmpty {
                        state = statusWords(status)
                    } else {
                        state = r.risk == "likely" ? "Tide · likely" : "Tide · possible"
                    }
                    rows.append(Row(name: r.name, state: state, note: r.headline ?? "", isClosed: closed))
                }
            default:
                continue
            }
        }
        return rows
    }

    /// The county's raw status in the board's short words.
    public static func statusWords(_ raw: String) -> String {
        switch raw.uppercased().trimmingCharacters(in: .whitespaces) {
        case "OPEN": return "Open"
        case "CLOSED FOR HIGH TIDE": return "Closed · high tide"
        case "CLOSED - CLEARED FOR TURTLES": return "Closed · turtles"
        case "CLOSED": return "Closed"
        default:
            return raw.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
    }

    /// The weekend-day facts, in order, for the day strip.
    public static func days(_ sources: [ChatSource]) -> [ChatSource] {
        sources.filter { $0.kind == "weekend_day" }
    }
}
