import Foundation

/// Server configuration from the `/api/v2/config` endpoint.
public struct AppConfig: Sendable {
    public let defaultCity: String
    public let tempStations: String
    public let tideStation: String
    public let waterTempAvg: Bool
    public let webcamURL: String?
    public let videoStreamURL: String?
}

extension AppConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case defaultCity = "default_city"
        case tempStations = "temp_stations"
        case tideStation = "tide_station"
        case waterTempAvg = "water_temp_avg"
        case webcamURL = "webcam_url"
        case videoStreamURL = "video_stream_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultCity = try container.decode(String.self, forKey: .defaultCity)
        tempStations = try container.decode(String.self, forKey: .tempStations)
        tideStation = try container.decode(String.self, forKey: .tideStation)
        waterTempAvg = (try? container.decode(Bool.self, forKey: .waterTempAvg)) ?? false
        webcamURL = try? container.decode(String.self, forKey: .webcamURL)
        videoStreamURL = try? container.decode(String.self, forKey: .videoStreamURL)
    }
}
