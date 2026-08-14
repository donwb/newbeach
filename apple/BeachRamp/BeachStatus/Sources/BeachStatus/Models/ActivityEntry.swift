import Foundation

/// A single ramp status change from the server's history log
/// (`GET /api/v2/activity`). Entries arrive newest-first.
public struct ActivityEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let accessID: String
    public let accessStatus: String
    public let recordedAt: Date
    public let rampName: String?
    public let city: String?

    public init(id: Int, accessID: String, accessStatus: String,
                recordedAt: Date, rampName: String? = nil, city: String? = nil) {
        self.id = id
        self.accessID = accessID
        self.accessStatus = accessStatus
        self.recordedAt = recordedAt
        self.rampName = rampName
        self.city = city
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accessID = "access_id"
        case accessStatus = "access_status"
        case recordedAt = "recorded_at"
        case rampName = "ramp_name"
        case city
    }

    /// Category derived from the raw status string (history entries do not
    /// carry a category column).
    public var category: StatusCategory {
        StatusCategory(accessStatus: accessStatus)
    }

    /// Display name for the ramp, e.g. "BEACHWAY AV" → "Beachway Av".
    public var rampDisplayName: String? {
        rampName?.titleCased
    }

    /// Sentence-cased status for display, e.g. "CLOSED FOR HIGH TIDE" →
    /// "Closed for high tide", "OPEN - ENTRANCE ONLY" → "Open — entrance only".
    public var statusDisplay: String {
        let lower = accessStatus.lowercased().replacingOccurrences(of: " - ", with: " — ")
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}
