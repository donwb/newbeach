import Foundation
import Testing
@testable import BeachStatus

struct ChatDecodingTests {
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private let payload = """
    {
      "reply": "Flagler Ave could close around the 2:30pm high tide on Friday. Closure possible around 2:30pm, often back open by ~4:30pm.",
      "sources": [
        {
          "kind": "ramp_outlook",
          "access_id": "NS-110", "name": "Flagler Ave", "city": "New Smyrna Beach",
          "at": "2026-06-12T18:00:00Z", "at_label": "Friday ~2pm",
          "risk": "possible", "reason": "high_tide",
          "headline": "Could close around the 2:30pm high tide",
          "detail": "Closure possible around 2:30pm · often back open by ~4:30pm",
          "window_label": "11:30am–5pm",
          "target_vs_hours": "inside"
        },
        {
          "kind": "city_now", "city": "New Smyrna Beach", "open_count": 4, "ramp_count": 5,
          "headline": "Four of five open", "detail": "Crawford Rd closed for the tide since 7:46am",
          "ramps": [
            {"access_id": "NS-108", "name": "Crawford Rd", "status": "CLOSED FOR HIGH TIDE", "risk": "closed_now", "headline": "Closed for high tide"},
            {"access_id": "NS-110", "name": "Flagler Av", "status": "OPEN", "risk": "scheduled", "headline": "Beach driving closes for the day around 6:30pm"}
          ]
        },
        {
          "kind": "weekend_day",
          "date": "2026-06-13", "weekday": "Saturday", "verdict": "great",
          "headline": "Clear all day", "closure_risk_label": "Clear all day",
          "best_window_label": "~9am–1pm"
        }
      ],
      "model": "claude-opus-5",
      "usage": { "input_tokens": 4100, "output_tokens": 220, "calls": 3 },
      "generated_at": "2026-06-10T13:00:00Z"
    }
    """

    @Test func decodesResponseWithBothSourceKinds() throws {
        let r = try decoder().decode(ChatResponse.self, from: Data(payload.utf8))
        #expect(r.reply.hasPrefix("Flagler Ave could close"))
        #expect(r.sources.count == 3)

        let ramp = r.sources[0]
        #expect(ramp.kind == "ramp_outlook")
        #expect(ramp.accessID == "NS-110")
        #expect(ramp.atLabel == "Friday ~2pm")
        #expect(ramp.risk == "possible")
        #expect(ramp.windowLabel == "11:30am–5pm")
        #expect(ramp.relation == "inside")
        #expect(ramp.at != nil)
        #expect(!ramp.isClosedNow)

        let city = r.sources[1]
        #expect(city.kind == "city_now")
        #expect(city.openCount == 4)
        #expect(city.rampCount == 5)
        #expect(city.ramps?.count == 2)
        #expect(city.ramps?[0].status == "CLOSED FOR HIGH TIDE")
        #expect(city.id == "city_now-New Smyrna Beach-")

        let day = r.sources[2]
        #expect(day.kind == "weekend_day")
        #expect(day.weekday == "Saturday")
        #expect(day.verdict == "great")
        #expect(day.bestWindowLabel == "~9am–1pm")
        #expect(day.accessID == nil)

        #expect(r.usage?.calls == 3)
        #expect(r.model == "claude-opus-5")
    }

    @Test func minimalResponseDecodes() throws {
        let r = try decoder().decode(ChatResponse.self, from: Data(#"{"reply":"hi","sources":[]}"#.utf8))
        #expect(r.reply == "hi")
        #expect(r.sources.isEmpty)
        #expect(r.generatedAt == nil)
    }

    @Test func requestEncodesSnakeCaseAndNoTurnIDs() throws {
        let req = ChatRequest(
            messages: [ChatTurn(role: .user, text: "hi"), ChatTurn(role: .assistant, text: "hello"), ChatTurn(role: .user, text: "Flagler at 2?")],
            context: ChatContext(accessID: "NS-110", city: "NEW SMYRNA BEACH")
        )
        let data = try JSONEncoder().encode(req)
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(obj["messages"] as? [[String: Any]])
        #expect(messages.count == 3)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[0]["id"] == nil, "client-side identity never goes on the wire")
        let ctx = try #require(obj["context"] as? [String: Any])
        #expect(ctx["access_id"] as? String == "NS-110")
        #expect(ctx["city"] as? String == "NEW SMYRNA BEACH")
    }

    @Test func turnsDecodeWithFreshIDs() throws {
        let turns = try decoder().decode([ChatTurn].self, from: Data(#"[{"role":"user","text":"a"},{"role":"assistant","text":"b"}]"#.utf8))
        #expect(turns.count == 2)
        #expect(turns[0].id != turns[1].id)
        #expect(turns[1].role == .assistant)
    }
}
