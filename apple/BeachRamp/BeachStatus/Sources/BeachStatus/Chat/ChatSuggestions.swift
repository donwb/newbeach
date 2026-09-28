import Foundation

/// Ready-made questions for the chat screens, written for the ramp on
/// screen and the time of day so most asks need no typing — the whole
/// point on Apple TV. These are questions, not predictions: "could close"
/// in a question is fine; the answer's wording comes from the engine.
public enum ChatSuggestions {
    public static let eastern = TimeZone(identifier: "America/New_York")!

    public static var easternCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern
        return cal
    }

    /// Three suggestions, written for the board's city — the common
    /// question is "can I get on the beach in NSB?", not one ramp. With a
    /// ramp on screen, the first question is about that ramp instead.
    public static func questions(city: String?, ramp: Ramp? = nil, now: Date, calendar: Calendar = easternCalendar) -> [String] {
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday
        let weekendDay = nextWeekendDayName(weekday: weekday)
        let later: String
        switch hour {
        case ..<12: later = "this afternoon"
        case 12..<17: later = "later today"
        default: later = "tomorrow morning"
        }

        let cityName = prettyCity(city)
        var out: [String] = []
        if let ramp {
            out.append("Is \(ramp.shortDisplayName) open right now?")
        } else if let cityName {
            out.append("Can I get on the beach in \(cityName) right now?")
        } else {
            out.append("Can I get on the beach right now?")
        }
        if let cityName {
            out.append("Will the \(cityName) ramps be open \(later)?")
        } else {
            out.append("Will the ramps be open \(later)?")
        }
        out.append(weekday == 7 || weekday == 1 ? "What does \(weekendDay) look like?" : "Which day this weekend is best?")
        return out
    }

    /// "NEW SMYRNA BEACH" → "New Smyrna Beach"; nil/empty stays nil.
    public static func prettyCity(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return raw.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The nearest upcoming weekend day that is not today: Saturday most
    /// of the week, Sunday on a Saturday, "next Saturday" on a Sunday.
    static func nextWeekendDayName(weekday: Int) -> String {
        switch weekday {
        case 7: return "Sunday"
        case 1: return "next Saturday"
        default: return "Saturday"
        }
    }
}
