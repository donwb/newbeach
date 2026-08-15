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
    /// Curated metadata from the server's ramp_metadata table. All nil until
    /// populated via the admin API — render nothing rather than placeholders.
    public let shortName: String?
    public let address: String?
    public let drivingHours: String?
    public let closureHeightFt: Double?
    /// Per-city driver order (1 = first). Nil sorts after any ordered ramp.
    public let sortOrder: Int?

    public init(id: Int, rampName: String, accessStatus: String, statusCategory: String,
                objectID: Int, city: String, accessID: String, location: String,
                lastUpdated: Date?, statusSince: Date? = nil,
                shortName: String? = nil, address: String? = nil, drivingHours: String? = nil,
                closureHeightFt: Double? = nil, sortOrder: Int? = nil) {
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
        self.shortName = shortName
        self.address = address
        self.drivingHours = drivingHours
        self.closureHeightFt = closureHeightFt
        self.sortOrder = sortOrder
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
        case shortName = "short_name"
        case address
        case drivingHours = "driving_hours"
        case closureHeightFt = "closure_height_ft"
        case sortOrder = "sort_order"
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

    /// Short display name for tight layouts (widget lists). Falls back to the
    /// full display name — never truncate with an ellipsis.
    public var shortDisplayName: String {
        shortName ?? rampDisplayName
    }
}

public extension Array where Element == Ramp {
    /// Board order: server-declared per-city `sort_order` first, unordered
    /// ramps after in name order.
    func boardOrdered() -> [Ramp] {
        sorted { a, b in
            switch (a.sortOrder, b.sortOrder) {
            case let (x?, y?): return x == y ? a.rampName < b.rampName : x < y
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.rampName < b.rampName
            }
        }
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
