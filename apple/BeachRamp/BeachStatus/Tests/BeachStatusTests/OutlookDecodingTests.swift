import Foundation
import Testing
@testable import BeachStatus

struct OutlookDecodingTests {
    private func decode(_ json: String) throws -> Outlook {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Outlook.self, from: Data(json.utf8))
    }

    /// A realistic turtle-season payload: one likely, one quiet, one closed.
    private let payload = """
    {
      "generated_at": "2026-08-16T14:10:00Z",
      "season": "turtle",
      "schedule": {
        "opens_label": "around 8am, once ramps are cleared for turtles",
        "closes_label": "7pm",
        "opens_at": "2026-08-17T12:00:00Z",
        "closes_at": "2026-08-16T23:00:00Z"
      },
      "tide": { "next_peak_ft": 3.1, "next_peak_at": "2026-08-16T19:42:00Z" },
      "ramps": [
        {
          "access_id": "NS-141", "ramp_id": 7, "risk": "likely",
          "confidence": "high",
          "headline": "High-tide closure likely around 1:30pm",
          "detail": "Often back open by 5pm once the tide drops",
          "short": "closure likely ~1:30pm",
          "window": { "label": "12:30\\u20136pm",
                      "start": "2026-08-16T16:30:00Z",
                      "end": "2026-08-16T22:00:00Z" }
        },
        {
          "access_id": "PI-097", "ramp_id": 22, "risk": "none",
          "confidence": "high",
          "headline": "No tide trouble expected",
          "detail": "Open for driving until 7pm"
        },
        {
          "access_id": "NS-106", "ramp_id": 3, "risk": "closed_now",
          "confidence": "medium",
          "headline": "Closed for high tide",
          "detail": "The tide is the boss here \\u00b7 often back open around 5pm",
          "reopen": { "label": "often back open around 5pm" }
        }
      ]
    }
    """

    @Test func decodesFullPayload() throws {
        let outlook = try decode(payload)
        #expect(outlook.season == "turtle")
        #expect(outlook.schedule.closesLabel == "7pm")
        #expect(outlook.schedule.opensAt != nil)
        #expect(outlook.tide.nextPeakFt == 3.1)
        #expect(outlook.ramps.count == 3)

        let likely = try #require(outlook.ramp(for: "NS-141"))
        #expect(likely.flagsRisk)
        #expect(likely.short == "closure likely ~1:30pm")
        #expect(likely.window?.label == "12:30–6pm")

        let quiet = try #require(outlook.ramp(for: "PI-097"))
        #expect(!quiet.flagsRisk)
        #expect(quiet.short == nil)
        #expect(quiet.window == nil)

        let closed = try #require(outlook.ramp(for: "NS-106"))
        #expect(!closed.flagsRisk, "closed_now is factual, not a hint")
        #expect(closed.reopen?.label == "often back open around 5pm")
    }

    @Test func unknownRiskDegradesGracefully() throws {
        let outlook = try decode("""
        {
          "generated_at": "2026-08-16T14:10:00Z",
          "season": "standard",
          "schedule": { "opens_label": "sunrise (~7am)", "closes_label": "sunset (~5:30pm)" },
          "tide": {},
          "ramps": [
            { "access_id": "NS-141", "ramp_id": 7, "risk": "imminent",
              "confidence": "low", "headline": "Something new" }
          ]
        }
        """)
        let ramp = try #require(outlook.ramp(for: "NS-141"))
        #expect(!ramp.flagsRisk, "future risk values must not surprise-render hints")
        #expect(outlook.schedule.opensAt == nil)
        #expect(outlook.tide.nextPeakFt == nil)
    }

    @Test func missingRampReturnsNil() throws {
        let outlook = try decode(payload)
        #expect(outlook.ramp(for: "XX-000") == nil)
    }

    @Test func boardHintAlwaysLooksForward() throws {
        let outlook = try decode(payload)
        // Tide-closed → the reopen estimate, never a blank.
        #expect(outlook.boardHint(forAccessID: "NS-106", category: .closed)
                == "often back open around 5pm")
        // Flagged drivable → the closure hint.
        #expect(outlook.boardHint(forAccessID: "NS-141", category: .open)
                == "closure likely ~1:30pm")
        // Quiet ramp → nothing.
        #expect(outlook.boardHint(forAccessID: "PI-097", category: .open) == nil)
        // Closed for a non-tide reason (no closed_now entry) → nothing.
        #expect(outlook.boardHint(forAccessID: "PI-097", category: .closed) == nil)
    }
}
