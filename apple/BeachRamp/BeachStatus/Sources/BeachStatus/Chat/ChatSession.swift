import Foundation
import Observation

/// How a session talks to the server. APIClient is the real one; tests and
/// previews substitute canned answers.
public protocol ChatTransport: Sendable {
    func send(_ request: ChatRequest, key: String) async throws -> ChatResponse
}

extension APIClient: ChatTransport {
    public func send(_ request: ChatRequest, key: String) async throws -> ChatResponse {
        try await sendChat(request, key: key)
    }
}

/// Where the chat key lives between launches.
public protocol ChatKeyStore: Sendable {
    func read() -> String?
    func write(_ key: String) throws
    func clear()
}

/// The Keychain-backed store the apps use.
public struct KeychainChatKeyStore: ChatKeyStore {
    public static let account = "chat-api-key"
    public init() {}
    public func read() -> String? { KeychainStore.read(account: Self.account) }
    public func write(_ key: String) throws { try KeychainStore.write(key, account: Self.account) }
    public func clear() { KeychainStore.delete(account: Self.account) }
}

/// In-memory store for tests and previews.
public final class InMemoryChatKeyStore: ChatKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    public init(_ value: String? = nil) { self.value = value }
    public func read() -> String? { lock.withLock { value } }
    public func write(_ key: String) throws { lock.withLock { value = key } }
    public func clear() { lock.withLock { value = nil } }
}

/// The transcript and its state, shared by the iOS and tvOS chat screens.
/// The session owns the key: a 401 or 503 flips `needsKey` and hands the
/// unsent question back as `draft`, so nothing the user typed is lost.
@MainActor
@Observable
public final class ChatSession {
    public private(set) var turns: [ChatTurn]
    /// Engine facts behind the most recent reply — the card under it.
    public private(set) var sources: [ChatSource]
    public private(set) var isPending = false
    /// A one-line problem to show under the transcript, cleared on the next send.
    public private(set) var errorText: String?
    /// The server wants a chat key we do not have (or have wrong).
    public private(set) var needsKey: Bool
    /// The server has no chat route (404): the feature is off.
    public private(set) var featureOff = false
    /// The city the board was showing when Ask opened. Most questions are
    /// about a city ("can I get on the beach in NSB?"), so questions that
    /// name no place are about it and the suggestions are written for it.
    /// Any spelling the server's city resolver knows ("NEW SMYRNA BEACH",
    /// "New Smyrna Beach", "NSB") works.
    public var contextCity: String?
    /// The ramp on screen, when one was; questions that name no ramp are
    /// about it.
    public var contextRamp: Ramp?
    /// Text for the input field: the unsent question after a key problem.
    public var draft = ""

    private let transport: ChatTransport
    private let keyStore: ChatKeyStore
    private var key: String?

    /// The server caps a transcript at 20 turns; the client trims to match.
    public static let maxTurns = 20

    public init(transport: ChatTransport = APIClient.shared,
                keyStore: ChatKeyStore = KeychainChatKeyStore(),
                seed: [ChatTurn] = [],
                sources: [ChatSource] = []) {
        self.transport = transport
        self.keyStore = keyStore
        self.turns = seed
        self.sources = sources
        let stored = keyStore.read()
        self.key = stored
        self.needsKey = stored == nil
    }

    public var hasKey: Bool { key != nil }

    /// Suggested questions for the current context, ready to send verbatim.
    public var suggestions: [String] {
        ChatSuggestions.questions(city: contextCity, ramp: contextRamp, now: Date())
    }

    /// Store the key and clear the key prompt. A Keychain failure keeps the
    /// key for this session only.
    public func saveKey(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        key = trimmed
        needsKey = false
        errorText = nil
        do {
            try keyStore.write(trimmed)
        } catch {
            errorText = "Couldn't save the key; it will be kept for this session only."
        }
    }

    public func forgetKey() {
        key = nil
        keyStore.clear()
        needsKey = true
    }

    /// Send one question. The transcript grows by the user turn and, on
    /// success, the assistant turn. Any failure removes the user turn and
    /// puts the text back in `draft`.
    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPending else { return }
        errorText = nil
        guard let key else {
            draft = trimmed
            needsKey = true
            return
        }

        let userTurn = ChatTurn(role: .user, text: trimmed)
        turns.append(userTurn)
        if turns.count > Self.maxTurns {
            turns.removeFirst(turns.count - Self.maxTurns)
            // Keep the alternation the server requires: the oldest kept
            // turn must be the user's.
            while let first = turns.first, first.role == .assistant {
                turns.removeFirst()
            }
        }
        draft = ""
        isPending = true
        defer { isPending = false }

        let request = ChatRequest(
            messages: turns,
            context: (contextRamp != nil || contextCity != nil)
                ? ChatContext(accessID: contextRamp?.accessID, city: contextCity) : nil
        )
        do {
            let response = try await transport.send(request, key: key)
            turns.append(ChatTurn(role: .assistant, text: response.reply))
            sources = response.sources
        } catch {
            turns.removeAll { $0.id == userTurn.id }
            draft = trimmed
            switch error {
            case APIError.httpError(statusCode: 401):
                needsKey = true
                errorText = "That chat key wasn't accepted."
            case APIError.httpError(statusCode: 503):
                needsKey = true
                errorText = "Chat isn't set up on the server yet."
            case APIError.httpError(statusCode: 404):
                featureOff = true
                errorText = "Ask is switched off right now."
            case APIError.httpError(statusCode: 504):
                errorText = "The outlook took too long to answer. Try again."
            default:
                errorText = "Couldn't reach the outlook. Try again in a moment."
            }
        }
    }

    /// Clear the transcript; the key and context stay.
    public func reset() {
        turns = []
        sources = []
        errorText = nil
        draft = ""
    }
}
