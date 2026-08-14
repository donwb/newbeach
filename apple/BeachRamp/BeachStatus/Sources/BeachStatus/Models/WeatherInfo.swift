import Foundation

/// Current conditions and multi-day forecast from the NWS API.
public struct WeatherInfo: Codable, Sendable {
    public let current: CurrentConditions
    public let forecast: [ForecastPeriod]

    public init(current: CurrentConditions, forecast: [ForecastPeriod]) {
        self.current = current
        self.forecast = forecast
    }
}

public struct CurrentConditions: Codable, Sendable {
    public let temperatureF: Double?
    public let windSpeed: String?
    public let windDirection: String?
    public let windGust: String?
    public let description: String?
    public let humidity: Double?
    public let icon: String?

    public init(temperatureF: Double? = nil, windSpeed: String? = nil,
                windDirection: String? = nil, windGust: String? = nil,
                description: String? = nil, humidity: Double? = nil, icon: String? = nil) {
        self.temperatureF = temperatureF
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.windGust = windGust
        self.description = description
        self.humidity = humidity
        self.icon = icon
    }

    enum CodingKeys: String, CodingKey {
        case temperatureF = "temperature_f"
        case windSpeed = "wind_speed"
        case windDirection = "wind_direction"
        case windGust = "wind_gust"
        case description
        case humidity
        case icon
    }

    /// Formatted temperature string (e.g. "72°").
    public var tempDisplay: String {
        guard let temperatureF else { return "--°" }
        return "\(Int(temperatureF))°"
    }

    /// Wind summary (e.g. "NE 12 mph").
    public var windDisplay: String {
        guard let windSpeed else { return "Calm" }
        if windSpeed == "0 mph" { return "Calm" }
        let dir = windDirection ?? ""
        return "\(dir) \(windSpeed)".trimmingCharacters(in: .whitespaces)
    }

    /// Gust text if present (e.g. "Gusts 25 mph").
    public var gustDisplay: String? {
        guard let windGust, !windGust.isEmpty else { return nil }
        return "Gusts \(windGust)"
    }
}

public struct ForecastPeriod: Codable, Identifiable, Sendable {
    public let name: String
    public let temperature: Int
    public let tempUnit: String
    public let windSpeed: String
    public let windDirection: String
    public let windGust: String?
    public let shortDescription: String
    public let detailedDescription: String
    public let isDaytime: Bool
    public let icon: String?

    public init(name: String, temperature: Int, tempUnit: String = "F",
                windSpeed: String = "", windDirection: String = "", windGust: String? = nil,
                shortDescription: String = "", detailedDescription: String = "",
                isDaytime: Bool = true, icon: String? = nil) {
        self.name = name
        self.temperature = temperature
        self.tempUnit = tempUnit
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.windGust = windGust
        self.shortDescription = shortDescription
        self.detailedDescription = detailedDescription
        self.isDaytime = isDaytime
        self.icon = icon
    }

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, temperature
        case tempUnit = "temp_unit"
        case windSpeed = "wind_speed"
        case windDirection = "wind_direction"
        case windGust = "wind_gust"
        case shortDescription = "short_description"
        case detailedDescription = "detailed_description"
        case isDaytime = "is_daytime"
        case icon
    }

    /// Formatted temperature (e.g. "72°F").
    public var tempDisplay: String {
        "\(temperature)°\(tempUnit)"
    }

    /// Short day label (e.g. "Mon" from "Monday").
    public var shortName: String {
        let parts = name.split(separator: " ")
        let base = String(parts.first ?? Substring(name))
        if base.count > 3 {
            return String(base.prefix(3))
        }
        return base
    }
}
