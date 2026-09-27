import Foundation
import Testing
@testable import BeachStatus

/// A transport that answers from a script and records what it was sent.
final class FakeChatTransport: ChatTransport, @unchecked Sendable {
    private let lock = NSLock()
    var results: [Result<ChatResponse, Error>]
    private(set) var requests: [(ChatRequest, String)] = []

    init(_ results: [Result<ChatResponse, Error>]) { self.results = results }

    func send(_ request: ChatRequest, key: String) async throws -> ChatResponse {
        lock.withLock { requests.append((request, key)) }
        let next: Result<ChatResponse, Error> = lock.withLock {
            results.isEmpty ? .failure(APIError.invalidResponse) : results.removeFirst()
        }
        return try next.get()
    }
}

@MainActor
struct ChatSessionTests {
    private let flagler = Ramp(
        id: 3, rampName: "FLAGLER AV", accessStatus: "OPEN", statusCategory: "open",
        objectID: 3, city: "NEW SMYRNA BEACH", accessID: "NS-110", location: "NEW SMYRNA BEACH",
        lastUpdated: nil, statusSince: nil
    )

    private let answer = ChatResponse(
        reply: "Flagler Ave could close around the 2:30pm high tide.",
        sources: [ChatSource(kind: "ramp_outlook", accessID: "NS-110", name: "Flagler Ave",
                             atLabel: "Friday ~2pm", risk: "possible",
                             headline: "Could close around the 2:30pm high tide")]
    )

    @Test func noStoredKeyMeansNeedsKey() async {
        let session = ChatSession(transport: FakeChatTransport([]), keyStore: InMemoryChatKeyStore())
        #expect(session.needsKey)
        #expect(!session.hasKey)

        await session.send("Flagler at 2?")
        #expect(session.turns.isEmpty, "nothing is sent without a key")
        #expect(session.draft == "Flagler at 2?", "the question waits in the box")
    }

    @Test func saveKeyThenSendAppendsBothTurnsAndSources() async {
        let transport = FakeChatTransport([.success(answer)])
        let store = InMemoryChatKeyStore()
        let session = ChatSession(transport: transport, keyStore: store)
        session.contextRamp = flagler

        session.saveKey("  secret  ")
        #expect(!session.needsKey)
        #expect(store.read() == "secret", "trimmed and persisted")

        await session.send("Will Flagler be open Friday at 2pm?")
        #expect(session.turns.count == 2)
        #expect(session.turns[0].role == .user)
        #expect(session.turns[1].role == .assistant)
        #expect(session.turns[1].text == answer.reply)
        #expect(session.sources.count == 1)
        #expect(session.draft.isEmpty)
        #expect(!session.isPending)

        let (request, key) = transport.requests[0]
        #expect(key == "secret")
        #expect(request.context?.accessID == "NS-110", "the on-screen ramp rides along")
        #expect(request.messages.count == 1)
    }

    @Test func unauthorizedRestoresDraftAndAsksForKey() async {
        let transport = FakeChatTransport([.failure(APIError.httpError(statusCode: 401))])
        let session = ChatSession(transport: transport, keyStore: InMemoryChatKeyStore("stale"))
        #expect(!session.needsKey)

        await session.send("Flagler at 2?")
        #expect(session.needsKey)
        #expect(session.turns.isEmpty, "the unsent turn is withdrawn")
        #expect(session.draft == "Flagler at 2?")
        #expect(session.errorText != nil)
    }

    @Test func notFoundMeansFeatureOff() async {
        let transport = FakeChatTransport([.failure(APIError.httpError(statusCode: 404))])
        let session = ChatSession(transport: transport, keyStore: InMemoryChatKeyStore("k"))
        await session.send("hi")
        #expect(session.featureOff)
        #expect(!session.needsKey)
        #expect(session.turns.isEmpty)
    }

    @Test func otherErrorsKeepTheKeyAndTheDraft() async {
        let transport = FakeChatTransport([.failure(APIError.httpError(statusCode: 502))])
        let session = ChatSession(transport: transport, keyStore: InMemoryChatKeyStore("k"))
        await session.send("hi")
        #expect(!session.needsKey)
        #expect(session.draft == "hi")
        #expect(session.errorText != nil)
    }

    @Test func transcriptIsTrimmedToTheServerCap() async {
        var seed: [ChatTurn] = []
        for i in 0..<ChatSession.maxTurns {
            seed.append(ChatTurn(role: i % 2 == 0 ? .user : .assistant, text: "t\(i)"))
        }
        let transport = FakeChatTransport([.success(answer)])
        let session = ChatSession(transport: transport, keyStore: InMemoryChatKeyStore("k"), seed: seed)
        await session.send("one more")
        let sent = transport.requests[0].0.messages
        #expect(sent.count <= ChatSession.maxTurns)
        #expect(sent.first?.role == .user, "alternation starts on the user")
        #expect(sent.last?.text == "one more")
    }

    @Test func resetClearsTranscriptNotKey() async {
        let session = ChatSession(transport: FakeChatTransport([.success(answer)]), keyStore: InMemoryChatKeyStore("k"))
        await session.send("hi")
        session.reset()
        #expect(session.turns.isEmpty)
        #expect(session.sources.isEmpty)
        #expect(session.hasKey)
    }
}
