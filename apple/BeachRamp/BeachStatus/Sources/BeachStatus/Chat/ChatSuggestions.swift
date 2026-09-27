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

    /// Three suggestions. With a ramp: a today/tomorrow open-at question, a
    /// tomorrow tide question, and the weekend. Without: the weekend and
    /// two day questions.
    public static func questions(for ramp: Ramp?, now: Date, calendar: Calendar = easternCalendar) -> [String] {
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday
        let weekendDay = nextWeekendDayName(weekday: weekday)

        guard let ramp else {
            return [
                "Which day this weekend is best?",
                "What does tomorrow look like?",
                "What does \(weekendDay) look like?",
            ]
        }

        let name = ramp.shortDisplayName
        let openAt: String
        switch hour {
        case ..<13: openAt = "Is \(name) open at 2pm today?"
        case 13..<16: openAt = "Is \(name) open at 5pm today?"
        default: openAt = "Is \(name) open tomorrow at 10am?"
        }
        return [
            openAt,
            "Could \(name) close for the tide tomorrow?",
            "Which day this weekend is best?",
        ]
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
