#if DEBUG
import Foundation
import BeachStatus

/// Static sample data for Xcode previews — no network. Times are anchored to
/// "today" so since-lines and tide facts read naturally in the canvas.
enum PreviewFixtures {
    static let eastern = TimeZone(identifier: "America/New_York")!

    static var easternCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern
        return cal
    }

    /// Today at the given Eastern wall-clock time.
    static func at(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
        let base = easternCalendar.date(byAdding: .day, value: dayOffset, to: Date())!
        return easternCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    }

    static func ramp(_ id: Int, _ name: String, _ status: String, since: Date?) -> Ramp {
        Ramp(id: id, rampName: name, accessStatus: status,
             statusCategory: StatusCategory(accessStatus: status).rawValue,
             objectID: id, city: "NEW SMYRNA BEACH", accessID: "NSB-\(id)",
             location: "NEW SMYRNA BEACH", lastUpdated: Date(), statusSince: since)
    }

    /// The five NSB ramps, all open.
    static let openRamps: [Ramp] = [
        ramp(1, "BEACHWAY AV", "OPEN", since: at(6, 2)),
        ramp(2, "CRAWFORD RD", "OPEN", since: at(6, 2)),
        ramp(3, "FLAGLER AV", "OPEN", since: at(6, 2)),
        ramp(4, "3RD AV", "OPEN", since: at(6, 2)),
        ramp(5, "27TH AV", "OPEN", since: at(16, 11, dayOffset: -1)),
    ]

    /// Crawford closed for high tide, Beachway entrance only, rest open.
    static let mixedRamps: [Ramp] = [
        ramp(1, "BEACHWAY AV", "OPEN - ENTRANCE ONLY", since: at(11, 15)),
        ramp(2, "CRAWFORD RD", "CLOSED FOR HIGH TIDE", since: at(12, 48)),
        ramp(3, "FLAGLER AV", "OPEN", since: at(6, 2)),
        ramp(4, "3RD AV", "OPEN", since: at(6, 2)),
        ramp(5, "27TH AV", "OPEN", since: at(16, 11, dayOffset: -1)),
    ]

    static let tide = TideInfo(
        tideDirection: "Falling",
        tidePercentage: 42,
        waterTempAvg: 82,
        waterTemps: [
            WaterTempReading(stationID: "8721604", stationName: "Trident Pier, Port Canaveral FL", tempF: 82),
            WaterTempReading(stationID: "8720218", stationName: "Mayport (Bar Pilots Dock), FL", tempF: 83),
        ],
        predictions: [
            TidePrediction(time: at(4, 40), type: "L", height: -0.1),
            TidePrediction(time: at(10, 44), type: "H", height: 2.8),
            TidePrediction(time: at(16, 57), type: "L", height: -0.1),
            TidePrediction(time: at(23, 7), type: "H", height: 2.8),
        ]
    )

    static let weather = WeatherInfo(
        current: CurrentConditions(
            temperatureF: 89, windSpeed: "9 mph", windDirection: "ENE",
            windGust: nil, description: "Mostly clear", humidity: 62, icon: nil
        ),
        forecast: [
            ForecastPeriod(name: "This Afternoon", temperature: 93, windSpeed: "5 to 10 mph",
                           windDirection: "ESE", shortDescription: "Chance showers and thunderstorms"),
            ForecastPeriod(name: "Tonight", temperature: 76, windSpeed: "0 to 10 mph",
                           windDirection: "S", shortDescription: "Slight chance showers, then mostly clear",
                           isDaytime: false),
            ForecastPeriod(name: "Saturday", temperature: 93, windSpeed: "0 to 10 mph",
                           windDirection: "S", shortDescription: "Sunny, then slight chance thunderstorms"),
            ForecastPeriod(name: "Saturday Night", temperature: 77, windSpeed: "5 to 10 mph",
                           windDirection: "S", shortDescription: "Mostly clear", isDaytime: false),
            ForecastPeriod(name: "Sunday", temperature: 96, windSpeed: "5 mph",
                           windDirection: "SSW", shortDescription: "Sunny, then slight chance showers"),
            ForecastPeriod(name: "Sunday Night", temperature: 77, windSpeed: "5 mph",
                           windDirection: "S", shortDescription: "Slight chance showers, then mostly clear",
                           isDaytime: false),
        ]
    )

    static let cameras: [Camera] = [
        Camera(id: "nsb", name: "New Smyrna Beach", location: "New Smyrna Beach",
               streamURL: "https://cams.donwb.com/nsb/index.m3u8"),
        Camera(id: "ponce-inlet", name: "Ponce Inlet", location: "Ponce Inlet",
               streamURL: "https://cams.donwb.com/ponce-inlet/index.m3u8"),
        Camera(id: "dunlawton", name: "Dunlawton", location: "Daytona Beach Shores",
               streamURL: "https://cams.donwb.com/dunlawton/index.m3u8"),
        Camera(id: "ormond-beach", name: "Ormond Beach", location: "Ormond Beach",
               streamURL: "https://cams.donwb.com/ormond-beach/index.m3u8"),
        Camera(id: "ormond-by-the-sea", name: "Ormond-By-The-Sea", location: "Ormond-By-The-Sea",
               streamURL: ""),
    ]

    static let activity: [ActivityEntry] = [
        ActivityEntry(id: 4, accessID: "NSB-2", accessStatus: "CLOSED FOR HIGH TIDE",
                      recordedAt: at(12, 48), rampName: "CRAWFORD RD", city: "NEW SMYRNA BEACH"),
        ActivityEntry(id: 3, accessID: "NSB-1", accessStatus: "OPEN - ENTRANCE ONLY",
                      recordedAt: at(11, 15), rampName: "BEACHWAY AV", city: "NEW SMYRNA BEACH"),
        ActivityEntry(id: 2, accessID: "NSB-4", accessStatus: "OPEN",
                      recordedAt: at(6, 2), rampName: "3RD AV", city: "NEW SMYRNA BEACH"),
        ActivityEntry(id: 1, accessID: "NSB-5", accessStatus: "OPEN",
                      recordedAt: at(16, 11, dayOffset: -1), rampName: "27TH AV", city: "NEW SMYRNA BEACH"),
    ]

    static var sunTimeline: SunTimeline {
        SunTimeline(day: Date(), solar: .newSmyrnaBeach,
                    calendar: easternCalendar, zone: eastern)
    }
}
#endif
