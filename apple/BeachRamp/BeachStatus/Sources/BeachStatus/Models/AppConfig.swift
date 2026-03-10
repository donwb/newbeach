import Foundation

/// Server configuration from the `/api/v2/config` endpoint.
public struct AppConfig: Codable, Sendable {
    public let defaultCity: String
    public let tempStations: String
    public let tideStation: String
    public let waterTempAvg: Double?
    public let webcamURL: String?

    enum CodingKeys: String, CodingKey {
        case defaultCity = "default_city"
        case tempStations = "temp_stations"
        case tideStation = "tide_station"
        case waterTempAvg = "water_temp_avg"
        case webcamURL = "webcam_url"
    }
}
