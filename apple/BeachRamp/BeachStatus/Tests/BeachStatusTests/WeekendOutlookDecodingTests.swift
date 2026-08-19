import Foundation
import Testing
@testable import BeachStatus

struct WeekendOutlookDecodingTests {
    private func decode(_ json: String) throws -> WeekendOutlook {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WeekendOutlook.self, from: Data(json.utf8))
    }

    /// A realistic mid-week payload: a full-forecast great Saturday, a
    /// heat-bound mixed Sunday, and a bare weekday with every optional absent.
    private let payload = """
    {
      "generated_at": "2026-08-19T14:10:00Z",
      "headline": "Saturday's the day this weekend — Sunday looks a mixed bag",
      "days": [
        {
          "date": "2026-08-19", "weekday": "Wednesday", "is_weekend": false,
          "verdict": "good",
          "basis": ["tide", "weather", "marine"],
          "headline": "Open all day, no tide trouble",
          "closure_pressure": "none",
          "schedule": { "opens_label": "around 8am", "closes_label": "7pm" },
          "high_temp_f": 91, "rain_chance_pct": 20, "wind_label": "ENE 9 mph"
        },
        {
          "date": "2026-08-22", "weekday": "Saturday", "is_weekend": true,
          "verdict": "great",
          "basis": ["tide", "weather", "marine"],
          "headline": "Wide open all day",
          "best_window": { "label": "~9am–1pm",
                           "start": "2026-08-22T13:00:00Z",
                           "end": "2026-08-22T17:00:00Z" },
          "closure_pressure": "none",
          "schedule": { "opens_label": "around 8am", "closes_label": "7pm" },
          "high_temp_f": 93, "feels_like_f": 105,
          "rain_chance_pct": 30, "wind_label": "ENE 12 mph"
        },
        {
          "date": "2026-08-23", "weekday": "Sunday", "is_weekend": true,
          "verdict": "mixed",
          "drivers": ["heat", "tide"],
          "basis": ["tide", "weather", "marine"],
          "headline": "Doable, but the heat's the story",
          "why": "the heat, feels like ~108° by midday",
          "detail": "Closure possible around the ~1:30pm high tide",
          "best_window": { "label": "~8–11am",
                           "start": "2026-08-23T12:00:00Z",
                           "end": "2026-08-23T15:00:00Z" },
          "closure_pressure": "some",
          "schedule": { "opens_label": "around 8am", "closes_label": "7pm" },
          "high_temp_f": 94, "feels_like_f": 108
        }
      ]
    }
    """

    @Test func decodesFullPayload() throws {
        let weekend = try decode(payload)
        #expect(weekend.headline.contains("Saturday"))
        #expect(weekend.days.count == 3)

        let saturday = weekend.days[1]
        #expect(saturday.isWeekend)
        #expect(saturday.verdict == "great")
        #expect(saturday.weekdayShort == "Sat")
        #expect(saturday.bestWindow?.label == "~9am–1pm")
        #expect(saturday.feelsLikeF == 105)
        #expect(saturday.why == nil)

        let sunday = weekend.days[2]
        #expect(sunday.drivers == ["heat", "tide"])
        #expect(sunday.why?.contains("heat") == true)
        #expect(sunday.closurePressure == "some")
        #expect(sunday.windLabel == nil)
    }

    @Test func weekendDaysFiltersToTheWeekend() throws {
        let weekend = try decode(payload)
        #expect(weekend.weekendDays.map(\.weekday) == ["Saturday", "Sunday"])
    }

    @Test func tideOnlyDayDecodesWithoutWeatherFields() throws {
        // No NWS coverage: basis says tide-only and every weather optional
        // is absent — must decode, not throw.
        let weekend = try decode("""
        {
          "generated_at": "2026-08-19T14:10:00Z",
          "headline": "The week ahead, day by day",
          "days": [
            {
              "date": "2026-08-24", "weekday": "Monday", "is_weekend": false,
              "verdict": "no_call",
              "basis": ["tide"],
              "headline": "Too far out to call",
              "closure_pressure": "none",
              "schedule": { "opens_label": "around 8am", "closes_label": "7pm" }
            }
          ]
        }
        """)
        let day = try #require(weekend.days.first)
        #expect(day.basis == ["tide"])
        #expect(day.highTempF == nil)
        #expect(day.bestWindow == nil)
        #expect(day.verdictDisplay == "no call")
    }

    @Test func unknownVerdictDegradesGracefully() throws {
        // The verdict vocabulary is a raw string on purpose: a new server
        // value must decode and display, never throw.
        let weekend = try decode("""
        {
          "generated_at": "2026-08-19T14:10:00Z",
          "headline": "The week ahead, day by day",
          "days": [
            {
              "date": "2026-08-25", "weekday": "Tuesday", "is_weekend": false,
              "verdict": "epic_but_new",
              "basis": ["tide"],
              "headline": "Something new",
              "closure_pressure": "none"
            }
          ]
        }
        """)
        let day = try #require(weekend.days.first)
        #expect(day.verdict == "epic_but_new")
        #expect(day.verdictDisplay == "epic but new")
        #expect(day.schedule == nil)
    }
}
