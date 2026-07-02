import Foundation
import Testing
@testable import BeachStatus

struct SolarCalculatorTests {
    /// Eastern time, used for interpreting NSB sun events.
    private var easternCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    /// 2026-06-18 18:00 UTC — a summer day in the conversation's "today".
    private var summerDay: Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 6, day: 18, hour: 18
        ).date!
    }

    @Test func sunriseBeforeSunset() throws {
        let (sunrise, sunset) = SolarCalculator.newSmyrnaBeach.events(
            on: summerDay, calendar: easternCalendar
        )
        let rise = try #require(sunrise)
        let set = try #require(sunset)
        #expect(rise < set)
    }

    @Test func summerSunEventsLandInExpectedHours() throws {
        let cal = easternCalendar
        let (sunrise, sunset) = SolarCalculator.newSmyrnaBeach.events(on: summerDay, calendar: cal)
        let riseHour = cal.component(.hour, from: try #require(sunrise))
        let setHour = cal.component(.hour, from: try #require(sunset))
        // NSB in mid-June: sunrise ~6:25 AM ET, sunset ~8:25 PM ET.
        #expect(riseHour == 6)
        #expect(setHour == 20)
    }

    @Test func altitudeIsPositiveAtLocalNoon() {
        let cal = easternCalendar
        let noon = cal.date(bySettingHour: 13, minute: 0, second: 0, of: summerDay)!
        // Just after solar noon in summer the sun is high overhead.
        #expect(SolarCalculator.newSmyrnaBeach.altitude(at: noon) > 60)
    }

    @Test func altitudeIsNegativeAtMidnight() {
        let cal = easternCalendar
        let midnight = cal.startOfDay(for: summerDay)
        #expect(SolarCalculator.newSmyrnaBeach.altitude(at: midnight) < 0)
    }

    @Test func altitudeNearHorizonAtSunrise() throws {
        let (sunrise, _) = SolarCalculator.newSmyrnaBeach.events(on: summerDay, calendar: easternCalendar)
        let rise = try #require(sunrise)
        // At sunrise the sun sits at the standard horizon altitude (-0.833°).
        #expect(abs(SolarCalculator.newSmyrnaBeach.altitude(at: rise) - (-0.833)) < 0.05)
    }

    @Test func sunIsRisingInTheMorningAndSettingInTheEvening() {
        let cal = easternCalendar
        let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: summerDay)!
        let evening = cal.date(bySettingHour: 18, minute: 0, second: 0, of: summerDay)!
        #expect(SolarCalculator.newSmyrnaBeach.isRising(at: morning))
        #expect(!SolarCalculator.newSmyrnaBeach.isRising(at: evening))
    }

    @Test func civilTwilightBracketsSunrise() throws {
        let cal = easternCalendar
        let solar = SolarCalculator.newSmyrnaBeach
        let dawn = try #require(solar.crossing(altitude: -6, rising: true, on: summerDay, calendar: cal))
        let (sunrise, _) = solar.events(on: summerDay, calendar: cal)
        let rise = try #require(sunrise)
        // Civil dawn precedes sunrise, and at that instant the sun sits at -6°.
        #expect(dawn < rise)
        #expect(abs(solar.altitude(at: dawn) - (-6)) < 0.05)
    }

    @Test func goldenHourBoundaryIsAboveSunriseAndSitsAtSixDegrees() throws {
        let cal = easternCalendar
        let solar = SolarCalculator.newSmyrnaBeach
        let goldenEnd = try #require(solar.crossing(altitude: 6, rising: true, on: summerDay, calendar: cal))
        let (sunrise, _) = solar.events(on: summerDay, calendar: cal)
        let rise = try #require(sunrise)
        // Morning golden hour ends (sun reaches +6°) after sunrise.
        #expect(goldenEnd > rise)
        #expect(abs(solar.altitude(at: goldenEnd) - 6) < 0.05)
    }

    @Test func descendingCrossingComesAfterAscendingCrossing() throws {
        let cal = easternCalendar
        let solar = SolarCalculator.newSmyrnaBeach
        let goldenAM = try #require(solar.crossing(altitude: 6, rising: true, on: summerDay, calendar: cal))
        let goldenPM = try #require(solar.crossing(altitude: 6, rising: false, on: summerDay, calendar: cal))
        #expect(goldenPM > goldenAM)
    }

    @Test func solarNoonFallsBetweenSunriseAndSunsetAtPeakAltitude() throws {
        let cal = easternCalendar
        let solar = SolarCalculator.newSmyrnaBeach
        let noon = solar.solarNoon(on: summerDay, calendar: cal)
        let (sunrise, sunset) = solar.events(on: summerDay, calendar: cal)
        let rise = try #require(sunrise)
        let set = try #require(sunset)
        #expect(noon > rise)
        #expect(noon < set)
        // Altitude at solar noon exceeds it an hour to either side.
        let before = noon.addingTimeInterval(-3600)
        let after = noon.addingTimeInterval(3600)
        #expect(solar.altitude(at: noon) > solar.altitude(at: before))
        #expect(solar.altitude(at: noon) > solar.altitude(at: after))
    }
}
