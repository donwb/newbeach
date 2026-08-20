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

    /// A mid-week six-day weekend outlook: a heat-capped Saturday, a clean
    /// Sunday, and a too-far-out Monday exercising the no_call look.
    static let weekend = WeekendOutlook(
        generatedAt: Date(),
        headline: "Sunday's the day this weekend — Saturday's a scorcher",
        days: [
            WeekendDay(date: "2026-08-19", weekday: "Wednesday", isWeekend: false,
                       verdict: "good", basis: ["tide", "weather", "marine"],
                       headline: "Open all day, no tide trouble",
                       closurePressure: "none",
                       highTempF: 91, rainChancePct: 20, windLabel: "ENE 9 mph"),
            WeekendDay(date: "2026-08-20", weekday: "Thursday", isWeekend: false,
                       verdict: "mixed", drivers: ["tide"],
                       basis: ["tide", "weather", "marine"],
                       headline: "Closure possible around the ~1:30pm high tide",
                       why: "around the ~1:30pm high tide",
                       bestWindow: OutlookWindow(label: "~8–11am",
                                                 start: at(8, 0, dayOffset: 1),
                                                 end: at(11, 0, dayOffset: 1)),
                       closurePressure: "some",
                       highTempF: 92, rainChancePct: 30, windLabel: "E 11 mph"),
            WeekendDay(date: "2026-08-21", weekday: "Friday", isWeekend: false,
                       verdict: "tough", drivers: ["storms"],
                       basis: ["tide", "weather", "marine"],
                       headline: "Storms most of the afternoon",
                       why: "storms, ~70% coverage",
                       closurePressure: "some",
                       highTempF: 88, rainChancePct: 70, windLabel: "SE 14 mph"),
            WeekendDay(date: "2026-08-22", weekday: "Saturday", isWeekend: true,
                       verdict: "mixed", drivers: ["heat"],
                       basis: ["tide", "weather", "marine"],
                       headline: "Doable, but the heat's the story",
                       why: "the heat, feels like ~108° by midday",
                       bestWindow: OutlookWindow(label: "~8–11am",
                                                 start: at(8, 0, dayOffset: 3),
                                                 end: at(11, 0, dayOffset: 3)),
                       closurePressure: "none",
                       highTempF: 94, feelsLikeF: 108, rainChancePct: 20,
                       windLabel: "SSW 8 mph"),
            WeekendDay(date: "2026-08-23", weekday: "Sunday", isWeekend: true,
                       verdict: "great", basis: ["tide", "weather", "marine"],
                       headline: "Wide open all day",
                       bestWindow: OutlookWindow(label: "~9am–1pm",
                                                 start: at(9, 0, dayOffset: 4),
                                                 end: at(13, 0, dayOffset: 4)),
                       closurePressure: "none",
                       highTempF: 90, rainChancePct: 10, windLabel: "ENE 12 mph"),
            WeekendDay(date: "2026-08-24", weekday: "Monday", isWeekend: false,
                       verdict: "no_call", basis: ["tide"],
                       headline: "Too far out to call",
                       closurePressure: "none"),
        ]
    )

    // MARK: - Video-first ledger fixtures

    /// The five NSB rows, resting state.
    static let nsbRows: [TVRampRowModel] = [
        TVRampRowModel(id: "NSB-1", name: "Beachway Ave", nowLabel: "Open",
                       isClosed: false, nextLabel: "could close on the ~3pm tide"),
        TVRampRowModel(id: "NSB-2", name: "Crawford Rd", nowLabel: "Open",
                       isClosed: false, nextLabel: "could close on the ~3pm tide"),
        TVRampRowModel(id: "NSB-3", name: "Flagler Ave", nowLabel: "Open",
                       isClosed: false, nextLabel: "Clear all day"),
        TVRampRowModel(id: "NSB-4", name: "3rd Ave", nowLabel: "Open",
                       isClosed: false, nextLabel: "closes for the day ~6:30pm"),
        TVRampRowModel(id: "NSB-5", name: "27th Ave", nowLabel: "Open",
                       isClosed: false, nextLabel: "Clear all day"),
    ]

    /// Twelve Daytona rows with two closures sorted to the top — exercises
    /// the windowed list, the scroll thumb, and the "12 · 7 below" header.
    static let daytonaRows: [TVRampRowModel] = [
        TVRampRowModel(id: "DB-1", name: "Harvey Ave", nowLabel: "Closed — high tide",
                       isClosed: true, nextLabel: "often back open around 5:30pm"),
        TVRampRowModel(id: "DB-2", name: "Van Ave", nowLabel: "Closed — high tide",
                       isClosed: true, nextLabel: "often back open around 5:30pm"),
    ] + (3...12).map { i in
        TVRampRowModel(id: "DB-\(i)", name: ["Main St", "Seabreeze Blvd", "Auditorium Blvd",
                                             "University Blvd", "Silver Beach Ave", "Botefuhr Ave",
                                             "International Speedway", "Hartford Ave", "Emilia Ave",
                                             "Zelda Blvd"][i - 3],
                       nowLabel: "Open", isClosed: false,
                       nextLabel: i.isMultiple(of: 2) ? "could close on the ~3pm tide" : "Clear all day")
    }

    static let overnightLines: [TVOvernightCityLine] = [
        TVOvernightCityLine(id: "New Smyrna Beach", city: "New Smyrna Beach",
                            closedLabel: "5 closed", reopenLabel: "opens around 8am"),
        TVOvernightCityLine(id: "Daytona Beach", city: "Daytona Beach",
                            closedLabel: "12 closed", reopenLabel: "opens around 8am"),
        TVOvernightCityLine(id: "Ormond Beach", city: "Ormond Beach",
                            closedLabel: "4 closed", reopenLabel: "opens around 8am"),
        TVOvernightCityLine(id: "Ponce Inlet", city: "Ponce Inlet",
                            closedLabel: "3 closed", reopenLabel: "opens around 8am"),
    ]

    /// Seven outlook table rows, one all-day risk exercising the red.
    static let outlookRows: [TVOutlookDayRow] = [
        TVOutlookDayRow(id: "d0", day: "Today", high: "91°", rain: "10%", surf: "Knee-high",
                        bestWindow: "9am–1pm", closureRisk: "Mid-day close potential",
                        isToday: true, isWorstRisk: false),
        TVOutlookDayRow(id: "d1", day: "Thursday", high: "92°", rain: "20%", surf: "Flat",
                        bestWindow: "8am–2pm", closureRisk: "Clear all day",
                        isToday: false, isWorstRisk: false),
        TVOutlookDayRow(id: "d2", day: "Friday", high: "93°", rain: "20%", surf: "Knee-high",
                        bestWindow: "8am–1pm", closureRisk: "Late-day close potential",
                        isToday: false, isWorstRisk: false),
        TVOutlookDayRow(id: "d3", day: "Saturday", high: "93°", rain: "20%", surf: "Knee-high",
                        bestWindow: "9am–1pm", closureRisk: "Mid-day close potential",
                        isToday: false, isWorstRisk: false),
        TVOutlookDayRow(id: "d4", day: "Sunday", high: "91°", rain: "10%", surf: "Waist-high",
                        bestWindow: "Any time", closureRisk: "Clear all day",
                        isToday: false, isWorstRisk: false),
        TVOutlookDayRow(id: "d5", day: "Monday", high: "89°", rain: "40%", surf: "Waist-high",
                        bestWindow: "Before 11am", closureRisk: "Morning close potential",
                        isToday: false, isWorstRisk: false),
        TVOutlookDayRow(id: "d6", day: "Tuesday", high: "88°", rain: "60%", surf: "Chest-high",
                        bestWindow: "No real window", closureRisk: "All-day close risk",
                        isToday: false, isWorstRisk: true),
    ]

    /// A day with a mid-day tide closure — exercises the today bar segments
    /// and the event log.
    static let intervals = RampIntervals(
        ramp: openRamps[1],
        windowStart: at(8, 0, dayOffset: -2),
        windowEnd: Date(),
        intervals: [
            RampInterval(status: "OPEN", category: "open",
                         start: at(8, 4, dayOffset: -2), end: at(11, 0, dayOffset: -2)),
            RampInterval(status: "CLOSED FOR HIGH TIDE", category: "closed",
                         start: at(11, 0, dayOffset: -2), end: at(14, 30, dayOffset: -2)),
            RampInterval(status: "OPEN", category: "open",
                         start: at(14, 30, dayOffset: -2), end: at(18, 37, dayOffset: -1)),
            RampInterval(status: "CLOSED", category: "closed",
                         start: at(18, 37, dayOffset: -1), end: at(7, 2)),
            RampInterval(status: "CLOSED - CLEARED FOR TURTLES", category: "closed",
                         start: at(7, 2), end: at(7, 59)),
            RampInterval(status: "OPEN", category: "open",
                         start: at(7, 59), end: Date()),
        ]
    )

    static let tideChart = TideChartData(
        currentTime: Date(),
        highLow: [
            TidePrediction(time: at(3, 4), type: "H", height: 2.0),
            TidePrediction(time: at(9, 23), type: "L", height: 0.3),
            TidePrediction(time: at(15, 51), type: "H", height: 2.5),
            TidePrediction(time: at(22, 23), type: "L", height: 0.6),
        ],
        hourly: []
    )
}
#endif
