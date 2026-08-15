import Foundation

/// Response of `/api/v2/health`. `ingester.lastPollAt` is the real GIS feed
/// timestamp — the input to the stale-feed state.
public struct HealthStatus: Codable, Sendable {
    public struct Ingester: Codable, Sendable {
        public let status: String
        public let lastPollAt: Date?
        public let lastCleanPollAt: Date?

        enum CodingKeys: String, CodingKey {
            case status
            case lastPollAt = "last_poll_at"
            case lastCleanPollAt = "last_clean_poll_at"
        }

        public init(status: String, lastPollAt: Date?, lastCleanPollAt: Date?) {
            self.status = status
            self.lastPollAt = lastPollAt
            self.lastCleanPollAt = lastCleanPollAt
        }
    }

    public let status: String
    public let database: String
    public let ingester: Ingester?

    public init(status: String, database: String, ingester: Ingester?) {
        self.status = status
        self.database = database
        self.ingester = ingester
    }
}
