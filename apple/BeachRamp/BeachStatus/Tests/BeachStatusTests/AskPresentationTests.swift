import Foundation
import Testing
@testable import BeachStatus

struct AskPresentationTests {
    @Test func splitLeadBreaksAtTheFirstSentence() {
        let (lead, rest) = AskPresentation.splitLead("Beach driving in NSB closes for the day around 6:30pm. Right now it's four of five open: Crawford Rd is closed. The rest look clear.")
        #expect(lead == "Beach driving in NSB closes for the day around 6:30pm.")
        #expect(rest == "Right now it's four of five open: Crawford Rd is closed. The rest look clear.")
    }

    @Test func splitLeadIgnoresDecimalsAndKeepsLongLeadsWhole() {
        let (lead, rest) = AskPresentation.splitLead("Water is 2.5 ft over normal. Ramps could close.")
        #expect(lead == "Water is 2.5 ft over normal.")
        #expect(rest == "Ramps could close.")

        let long = String(repeating: "word ", count: 40) + "end. Tail."
        let (l2, r2) = AskPresentation.splitLead(long)
        #expect(l2 == long)
        #expect(r2 == "")

        let (l3, r3) = AskPresentation.splitLead("No punctuation at all")
        #expect(l3 == "No punctuation at all")
        #expect(r3 == "")
    }

    @Test func kickerFollowsTheFactKind() {
        let now = ChatSource(kind: "city_now", city: "New Smyrna Beach", openCount: 4, rampCount: 5)
        #expect(AskPresentation.kicker(for: [now]) == "New Smyrna Beach · right now · 4 of 5 open")

        let at = ChatSource(kind: "city_outlook", city: "Daytona Beach", atLabel: "Saturday ~2pm", rampCount: 8)
        #expect(AskPresentation.kicker(for: [at]) == "Daytona Beach · Saturday ~2pm")

        let ramp = ChatSource(kind: "ramp_outlook", name: "Flagler Av", atLabel: "Friday ~2pm")
        #expect(AskPresentation.kicker(for: [ramp]) == "Flagler Av · Friday ~2pm")

        let day = ChatSource(kind: "weekend_day", weekday: "Saturday", verdict: "great")
        #expect(AskPresentation.kicker(for: [day]) == "The week ahead")
        #expect(AskPresentation.kicker(for: []) == nil)
    }

    @Test func newsRowsKeepOnlyClosuresAndRisks() {
        let now = ChatSource(kind: "city_now", city: "New Smyrna Beach", openCount: 4, rampCount: 5, ramps: [
            ChatSourceRamp(accessID: "NS-141", name: "27th Av", status: "OPEN", risk: "scheduled", headline: "Beach driving closes for the day around 6:30pm"),
            ChatSourceRamp(accessID: "NS-108", name: "Crawford Rd", status: "CLOSED FOR HIGH TIDE", risk: "closed_now", headline: "Closed for high tide"),
            ChatSourceRamp(accessID: "NS-110", name: "Flagler Av", status: "OPEN", risk: "possible", headline: "Could close around the 3pm high tide"),
        ])
        let rows = AskPresentation.newsRows([now])
        #expect(rows.count == 2)
        #expect(rows[0].name == "Crawford Rd")
        #expect(rows[0].state == "Closed · high tide")
        #expect(rows[0].isClosed)
        #expect(rows[1].name == "Flagler Av")
        #expect(rows[1].state == "Open")
        #expect(!rows[1].isClosed)

        let at = ChatSource(kind: "city_outlook", city: "Daytona Beach", atLabel: "Saturday ~2pm", ramps: [
            ChatSourceRamp(accessID: "DB-051", name: "Seabreeze Blvd", risk: "scheduled", headline: "Closes for the day"),
            ChatSourceRamp(accessID: "DB-041", name: "Boylston Av", risk: "possible", headline: "Could close around the 3pm high tide"),
        ])
        let future = AskPresentation.newsRows([at])
        #expect(future.count == 1)
        #expect(future[0].state == "Tide · possible")
    }

    @Test func statusWords() {
        #expect(AskPresentation.statusWords("CLOSED - CLEARED FOR TURTLES") == "Closed · turtles")
        #expect(AskPresentation.statusWords("OPEN") == "Open")
        #expect(AskPresentation.statusWords("LIMITED ACCESS") == "Limited Access")
    }
}
