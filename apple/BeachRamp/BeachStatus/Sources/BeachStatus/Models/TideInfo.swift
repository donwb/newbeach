import Foundation

/// Tide information from the NOAA API.
public struct TideInfo: Codable, Sendable {
    public let tideDirection: String
    public let tidePercentage: Int
    public let waterTempAvg: Double?
    public let waterTemps: [WaterTempReading]?
    public let predictions: [TidePrediction]?

    public init(tideDirection: String, tidePercentage: Int,
                waterTempAvg: Double? = nil, waterTemps: [WaterTempReading]? = nil,
                predictions: [TidePrediction]? = nil) {
        self.tideDirection = tideDirection
        self.tidePercentage = tidePercentage
        self.waterTempAvg = waterTempAvg
        self.waterTemps = waterTemps
        self.predictions = predictions
    }

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

    public init(stationID: String, stationName: String, tempF: Double) {
        self.stationID = stationID
        self.stationName = stationName
        self.tempF = tempF
    }

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
    /// Predicted water level in feet (MLLW). Nil on older server responses.
    public let height: Double?

    public init(time: Date, type: String, height: Double? = nil) {
        self.time = time
        self.type = type
        self.height = height
    }

    public var id: Date { time }

    /// "High" or "Low" display label.
    public var label: String {
        type == "H" ? "High" : "Low"
    }

    /// Formatted time string.
    public var timeDisplay: String {
        time.formatted(date: .omitted, time: .shortened)
    }

    /// Height formatted for display, e.g. "−0.1 ft" / "2.8 ft".
    public var heightDisplay: String? {
        guard let height else { return nil }
        let rounded = (height * 10).rounded() / 10
        let text = String(format: "%.1f ft", abs(rounded))
        return rounded < 0 ? "−\(text)" : text
    }
}

/// Data for rendering the tide chart.
public struct TideChartData: Codable, Sendable {
    public let currentTime: Date
    public let highLow: [TidePrediction]
    public let hourly: [HourlyTidePoint]

    public init(currentTime: Date, highLow: [TidePrediction], hourly: [HourlyTidePoint]) {
        self.currentTime = currentTime
        self.highLow = highLow
        self.hourly = hourly
    }

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
