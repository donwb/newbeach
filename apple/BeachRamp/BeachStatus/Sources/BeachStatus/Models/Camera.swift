import Foundation

/// A single live beach webcam from the `/api/v2/cameras` roster.
public struct Camera: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let location: String
    public let streamURL: String

    public init(id: String, name: String, location: String, streamURL: String) {
        self.id = id
        self.name = name
        self.location = location
        self.streamURL = streamURL
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case location
        case streamURL = "stream_url"
    }

    /// The stream URL as a `URL`, or `nil` if not yet resolved (empty string,
    /// e.g. a camera the home cron hasn't populated yet).
    public var url: URL? {
        streamURL.isEmpty ? nil : URL(string: streamURL)
    }
}

/// The `/api/v2/cameras` response: the ordered roster plus the default camera id.
public struct CameraRoster: Codable, Sendable {
    public let cameras: [Camera]
    public let defaultID: String

    public init(cameras: [Camera], defaultID: String) {
        self.cameras = cameras
        self.defaultID = defaultID
    }

    enum CodingKeys: String, CodingKey {
        case cameras
        case defaultID = "default_id"
    }

    /// The default camera, or the first in the roster, or nil if empty.
    public var defaultCamera: Camera? {
        cameras.first { $0.id == defaultID } ?? cameras.first
    }
}
