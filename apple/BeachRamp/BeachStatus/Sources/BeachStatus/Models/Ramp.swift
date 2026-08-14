import Foundation

/// A beach access ramp with its current status.
public struct Ramp: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let rampName: String
    public let accessStatus: String
    public let statusCategory: String
    public let objectID: Int
    public let city: String
    public let accessID: String
    public let location: String
    public let lastUpdated: Date?
    /// When the ramp's current status took effect (most recent history entry).
    /// Nil when the server has no recorded status change for this ramp.
    public let statusSince: Date?

    public init(id: Int, rampName: String, accessStatus: String, statusCategory: String,
                objectID: Int, city: String, accessID: String, location: String,
                lastUpdated: Date?, statusSince: Date? = nil) {
        self.id = id
        self.rampName = rampName
        self.accessStatus = accessStatus
        self.statusCategory = statusCategory
        self.objectID = objectID
        self.city = city
        self.accessID = accessID
        self.location = location
        self.lastUpdated = lastUpdated
        self.statusSince = statusSince
    }

    enum CodingKeys: String, CodingKey {
        case id
        case rampName = "ramp_name"
        case accessStatus = "access_status"
        case statusCategory = "status_category"
        case objectID = "object_id"
        case city
        case accessID = "access_id"
        case location
        case lastUpdated = "last_updated"
        case statusSince = "status_since"
    }

    /// Normalized status category for UI display.
    public var category: StatusCategory {
        StatusCategory(rawValue: statusCategory) ?? .closed
    }

    /// Display name for the ramp, e.g. "BEACHWAY AV" → "Beachway Av",
    /// "27TH AV" → "27th Av".
    public var rampDisplayName: String {
        rampName.titleCased
    }

    /// Title-cased city name (GIS data arrives uppercase).
    public var cityDisplay: String {
        city.titleCased
    }

    /// Title-cased location string.
    public var locationDisplay: String {
        location.titleCased
    }
}

public enum StatusCategory: String, Codable, CaseIterable, Sendable {
    case open
    case limited
    case closed

    /// Maps a raw county access status string to a category. Mirrors the
    /// server's StatusToCategory so history entries (which carry only the
    /// raw string) can be categorized client-side.
    public init(accessStatus: String) {
        switch accessStatus.trimmingCharacters(in: .whitespaces).uppercased() {
        case "OPEN":
            self = .open
        case "4X4 ONLY", "CLOSING IN PROGRESS", "OPEN - ENTRANCE ONLY":
            self = .limited
        default:
            self = .closed
        }
    }
}
