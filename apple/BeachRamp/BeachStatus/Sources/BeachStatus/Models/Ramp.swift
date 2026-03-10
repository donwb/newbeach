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

    public init(id: Int, rampName: String, accessStatus: String, statusCategory: String,
                objectID: Int, city: String, accessID: String, location: String, lastUpdated: Date?) {
        self.id = id
        self.rampName = rampName
        self.accessStatus = accessStatus
        self.statusCategory = statusCategory
        self.objectID = objectID
        self.city = city
        self.accessID = accessID
        self.location = location
        self.lastUpdated = lastUpdated
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
    }

    /// Normalized status category for UI display.
    public var category: StatusCategory {
        StatusCategory(rawValue: statusCategory) ?? .closed
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
}
