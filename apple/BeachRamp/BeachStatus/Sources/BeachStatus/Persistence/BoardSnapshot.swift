import Foundation

/// The last good board, persisted to the App Group so the widget extension
/// always has something honest to render before (or instead of) a network
/// fetch. Written by the app after every successful load.
public struct BoardSnapshot: Codable, Sendable {
    public let ramps: [Ramp]
    public let tide: TideInfo?
    public let tideChart: TideChartData?
    public let weather: WeatherInfo?
    /// Server open/close prediction; optional so snapshots written by older
    /// app builds still decode.
    public let outlook: Outlook?
    public let fetchedAt: Date

    public init(ramps: [Ramp], tide: TideInfo?, tideChart: TideChartData?,
                weather: WeatherInfo?, outlook: Outlook? = nil, fetchedAt: Date) {
        self.ramps = ramps
        self.tide = tide
        self.tideChart = tideChart
        self.weather = weather
        self.outlook = outlook
        self.fetchedAt = fetchedAt
    }

    /// Age of the snapshot relative to `now`.
    public func age(now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(fetchedAt)
    }
}
