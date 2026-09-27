import Foundation
import Testing
@testable import BeachStatus

struct ChatSuggestionsTests {
    private var cal: Calendar { ChatSuggestions.easternCalendar }

    /// An Eastern instant in June 2026 (the 10th is a Wednesday).
    private func et(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
    }

    private let flagler = Ramp(
        id: 3, rampName: "FLAGLER AV", accessStatus: "OPEN", statusCategory: "open",
        objectID: 3, city: "NEW SMYRNA BEACH", accessID: "NS-110", location: "NEW SMYRNA BEACH",
        lastUpdated: nil, statusSince: nil
    )

    @Test func morningAsksAboutThisAfternoon() {
        let q = ChatSuggestions.questions(for: flagler, now: et(10, 9), calendar: cal)
        #expect(q.count == 3)
        #expect(q[0] == "Is Flagler Av open at 2pm today?")
        #expect(q[1] == "Could Flagler Av close for the tide tomorrow?")
        #expect(q[2] == "Which day this weekend is best?")
    }

    @Test func midAfternoonAsksAboutFive() {
        let q = ChatSuggestions.questions(for: flagler, now: et(10, 14), calendar: cal)
        #expect(q[0] == "Is Flagler Av open at 5pm today?")
    }

    @Test func eveningRollsToTomorrow() {
        let q = ChatSuggestions.questions(for: flagler, now: et(10, 18), calendar: cal)
        #expect(q[0] == "Is Flagler Av open tomorrow at 10am?")
    }

    @Test func withoutARampAsksAboutDays() {
        let wed = ChatSuggestions.questions(for: nil, now: et(10, 9), calendar: cal)
        #expect(wed == ["Which day this weekend is best?", "What does tomorrow look like?", "What does Saturday look like?"])

        let sat = ChatSuggestions.questions(for: nil, now: et(13, 9), calendar: cal)
        #expect(sat[2] == "What does Sunday look like?")

        let sun = ChatSuggestions.questions(for: nil, now: et(14, 9), calendar: cal)
        #expect(sun[2] == "What does next Saturday look like?")
    }
}
