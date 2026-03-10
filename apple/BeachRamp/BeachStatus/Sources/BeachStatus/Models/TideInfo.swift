import Foundation

/// Tide information from the NOAA API.
public struct TideInfo: Codable, Sendable {
    public let tideDirection: String
    public let tidePercentage: Int
    public let waterTempAvg: Double?
    public let waterTemps: [WaterTempReading]?
    public let predictions: [TidePrediction]?

    enum CodingKeys: String, CodingKey {
        case tideDirection = "tide_direction"
        case tidePercentage = "tide_percentage"
        case waterTempAvg = "water_temp_avg"
        case waterTemps = "water_temps"
        case predictions
    }

    /// Whether the tide is currently rising.
    public var isRising: Bool {
        tideDirection == "Rising"
    }
}

public struct WaterTempReading: Codable, Identifiable, Sendable {
    public let stationID: String
    public let stationName: String
    public let tempF: Double

    public var id: String { stationID }

    enum CodingKeys: String, CodingKey {
        case stationID = "station_id"
        case stationName = "station_name"
        case tempF = "temp_f"
    }
}

public struct TidePrediction: Codable, Identifiable, Sendable {
    public let time: Date
    public let type: String

    public var id: Date { time }

    /// "High" or "Low" display label.
    public var label: String {
        type == "H" ? "High" : "Low"
    }

    /// Formatted time string.
    public var timeDisplay: String {
        time.formatted(date: .omitted, time: .shortened)
    }
}

/// Data for rendering the tide chart.
public struct TideChartData: Codable, Sendable {
    public let currentTime: Date
    public let highLow: [TidePrediction]
    public let hourly: [HourlyTidePoint]

    enum CodingKeys: String, CodingKey {
        case currentTime = "current_time"
        case highLow = "high_low"
        case hourly
    }
}

public struct HourlyTidePoint: Codable, Identifiable, Sendable {
    public let time: Date
    public let height: Double

    public var id: Date { time }
}
