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

    @Test func cityQuestionsFollowTheHour() {
        let morning = ChatSuggestions.questions(city: "NEW SMYRNA BEACH", now: et(10, 9), calendar: cal)
        #expect(morning == [
            "Can I get on the beach in New Smyrna Beach right now?",
            "Will the New Smyrna Beach ramps be open this afternoon?",
            "Which day this weekend is best?",
        ])
        let afternoon = ChatSuggestions.questions(city: "DAYTONA BEACH", now: et(10, 14), calendar: cal)
        #expect(afternoon[1] == "Will the Daytona Beach ramps be open later today?")
        let evening = ChatSuggestions.questions(city: "Ormond Beach", now: et(10, 18), calendar: cal)
        #expect(evening[1] == "Will the Ormond Beach ramps be open tomorrow morning?")
    }

    @Test func rampOnScreenLeadsWithTheRamp() {
        let q = ChatSuggestions.questions(city: "NEW SMYRNA BEACH", ramp: flagler, now: et(10, 9), calendar: cal)
        #expect(q[0] == "Is Flagler Av open right now?")
        #expect(q[1] == "Will the New Smyrna Beach ramps be open this afternoon?")
    }

    @Test func noCityStillAsks() {
        let q = ChatSuggestions.questions(city: nil, now: et(10, 9), calendar: cal)
        #expect(q[0] == "Can I get on the beach right now?")
        #expect(q[1] == "Will the ramps be open this afternoon?")
    }

    @Test func weekendDaysAskAboutTheOtherDay() {
        let sat = ChatSuggestions.questions(city: "NEW SMYRNA BEACH", now: et(13, 9), calendar: cal)
        #expect(sat[2] == "What does Sunday look like?")
        let sun = ChatSuggestions.questions(city: "NEW SMYRNA BEACH", now: et(14, 9), calendar: cal)
        #expect(sun[2] == "What does next Saturday look like?")
    }

    @Test func prettyCity() {
        #expect(ChatSuggestions.prettyCity("DAYTONA BEACH SHORES") == "Daytona Beach Shores")
        #expect(ChatSuggestions.prettyCity("") == nil)
        #expect(ChatSuggestions.prettyCity(nil) == nil)
    }
}
