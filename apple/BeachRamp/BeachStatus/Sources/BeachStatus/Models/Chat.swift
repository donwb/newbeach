import Foundation

// Wire types for POST /api/v2/chat ("Ask"). The server is stateless: the
// client sends the whole transcript every turn and gets back the next
// assistant turn plus the engine facts (`sources`) it rested on. Enum-like
// fields stay raw strings so new server values degrade gracefully, the same
// contract as Outlook.

public enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

/// One message in the transcript. `id` is client-side only (list identity);
/// it is never sent.
public struct ChatTurn: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let role: ChatRole
    public let text: String

    public init(role: ChatRole, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
    }

    enum CodingKeys: String, CodingKey { case role, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.role = try c.decode(ChatRole.self, forKey: .role)
        self.text = try c.decode(String.self, forKey: .text)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(text, forKey: .text)
    }
}

/// What the board was showing when they asked — the selected city and, when
/// a ramp was open, that ramp. A question that names no place is about the
/// city; one that names no ramp is about the ramp, if any.
public struct ChatContext: Codable, Hashable, Sendable {
    public let accessID: String?
    public let city: String?

    public init(accessID: String? = nil, city: String? = nil) {
        self.accessID = accessID
        self.city = city
    }

    enum CodingKeys: String, CodingKey {
        case accessID = "access_id"
        case city
    }
}

public struct ChatRequest: Codable, Hashable, Sendable {
    public let messages: [ChatTurn]
    public let context: ChatContext?

    public init(messages: [ChatTurn], context: ChatContext? = nil) {
        self.messages = messages
        self.context = context
    }
}

/// One engine fact the reply rested on. `kind` is `ramp_outlook` or
/// `weekend_day`; the rest is populated per kind. Render the strings
/// verbatim — they are the board's own copy.
public struct ChatSource: Codable, Hashable, Sendable, Identifiable {
    public var id: String {
        switch kind {
        case "weekend_day": return "day-" + (date ?? weekday ?? "")
        default: return "ramp-" + (accessID ?? "") + "-" + (atLabel ?? "")
        }
    }

    public let kind: String

    // ramp_outlook
    public let accessID: String?
    public let name: String?
    public let city: String?
    public let at: Date?
    public let atLabel: String?
    public let risk: String?
    public let reason: String?
    public let headline: String?
    public let detail: String?
    public let windowLabel: String?
    public let reopenLabel: String?
    public let relation: String?

    // weekend_day
    public let date: String?
    public let weekday: String?
    public let verdict: String?
    public let closureRiskLabel: String?
    public let bestWindowLabel: String?

    public init(kind: String, accessID: String? = nil, name: String? = nil, city: String? = nil,
                at: Date? = nil, atLabel: String? = nil, risk: String? = nil, reason: String? = nil,
                headline: String? = nil, detail: String? = nil, windowLabel: String? = nil,
                reopenLabel: String? = nil, relation: String? = nil, date: String? = nil,
                weekday: String? = nil, verdict: String? = nil, closureRiskLabel: String? = nil,
                bestWindowLabel: String? = nil) {
        self.kind = kind
        self.accessID = accessID
        self.name = name
        self.city = city
        self.at = at
        self.atLabel = atLabel
        self.risk = risk
        self.reason = reason
        self.headline = headline
        self.detail = detail
        self.windowLabel = windowLabel
        self.reopenLabel = reopenLabel
        self.relation = relation
        self.date = date
        self.weekday = weekday
        self.verdict = verdict
        self.closureRiskLabel = closureRiskLabel
        self.bestWindowLabel = bestWindowLabel
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case accessID = "access_id"
        case name, city, at
        case atLabel = "at_label"
        case risk, reason, headline, detail
        case windowLabel = "window_label"
        case reopenLabel = "reopen_label"
        case relation = "target_vs_hours"
        case date, weekday, verdict
        case closureRiskLabel = "closure_risk_label"
        case bestWindowLabel = "best_window_label"
    }

    /// The fact is a live closure (`closed_now`) — the one red thing.
    public var isClosedNow: Bool { risk == "closed_now" }
}

public struct ChatUsage: Codable, Hashable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let calls: Int

    public init(inputTokens: Int, outputTokens: Int, calls: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.calls = calls
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case calls
    }
}

public struct ChatResponse: Codable, Hashable, Sendable {
    public let reply: String
    public let sources: [ChatSource]
    public let model: String?
    public let usage: ChatUsage?
    public let generatedAt: Date?

    public init(reply: String, sources: [ChatSource], model: String? = nil,
                usage: ChatUsage? = nil, generatedAt: Date? = nil) {
        self.reply = reply
        self.sources = sources
        self.model = model
        self.usage = usage
        self.generatedAt = generatedAt
    }

    enum CodingKeys: String, CodingKey {
        case reply, sources, model, usage
        case generatedAt = "generated_at"
    }
}
