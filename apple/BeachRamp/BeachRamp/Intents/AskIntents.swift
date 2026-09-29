import AppIntents
import BeachStatus

// "Hey Siri, ask Beach Info …" — App Intents over the same Ask endpoint the
// board uses. Siri gives an intent a few seconds, so the common shapes are
// answered by the server's quick path (engine copy, no model) and only a
// free-form question reaches a model, on the faster voice tier. Siri reads
// the reply's spoken form; it is the outlook's own words either way.

/// The cities the county drives on, south to north.
enum BeachCity: String, AppEnum {
    case ponceInlet = "PONCE INLET"
    case newSmyrnaBeach = "NEW SMYRNA BEACH"
    case daytonaBeachShores = "DAYTONA BEACH SHORES"
    case daytonaBeach = "DAYTONA BEACH"
    case ormondBeach = "ORMOND BEACH"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "City")
    static let caseDisplayRepresentations: [BeachCity: DisplayRepresentation] = [
        .ponceInlet: "Ponce Inlet",
        .newSmyrnaBeach: "New Smyrna Beach",
        .daytonaBeachShores: "Daytona Beach Shores",
        .daytonaBeach: "Daytona Beach",
        .ormondBeach: "Ormond Beach",
    ]
}

/// Shared plumbing: the stored chat key, one request, one dialog.
enum AskService {
    static func ask(_ question: String, city: BeachCity?) async throws -> IntentDialog {
        guard let key = KeychainChatKeyStore().read() else {
            return IntentDialog("Open Beach Info and enter the chat key first, then I can answer.")
        }
        let request = ChatRequest(
            messages: [ChatTurn(role: .user, text: question)],
            context: city.map { ChatContext(city: $0.rawValue) },
            voice: true
        )
        do {
            let response = try await APIClient.shared.sendChat(request, key: key)
            return IntentDialog(stringLiteral: response.speech)
        } catch APIError.httpError(statusCode: 401), APIError.httpError(statusCode: 503) {
            return IntentDialog("The chat key wasn't accepted. Open Beach Info to enter it again.")
        } catch APIError.httpError(statusCode: 404) {
            return IntentDialog("Ask is switched off right now.")
        } catch {
            return IntentDialog("I couldn't reach the outlook. Try again in a moment.")
        }
    }
}

/// Free-form: "Hey Siri, ask Beach Info" → "What do you want to know?"
struct AskBeachIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask about the beach"
    static let description = IntentDescription("Ask whether you can get on the beach, whether the ramps will be open at a time this week, or which day looks best. Answers are the outlook's own words.")
    static let openAppWhenRun = false

    @Parameter(title: "Question", requestValueDialog: "What do you want to know about the beach?")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await AskService.ask(question, city: nil)
        return .result(dialog: dialog)
    }
}

/// One-shot: "Hey Siri, is the beach open in New Smyrna Beach with Beach Info".
struct BeachOpenNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Is the beach open?"
    static let description = IntentDescription("Whether you can drive on the beach in a city right now, and which ramps are open.")
    static let openAppWhenRun = false

    @Parameter(title: "City", requestValueDialog: "Which city?")
    var city: BeachCity

    static var parameterSummary: some ParameterSummary {
        Summary("Is the beach open in \(\.$city)?")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = BeachCity.caseDisplayRepresentations[city]?.title ?? LocalizedStringResource(stringLiteral: city.rawValue)
        let dialog = try await AskService.ask("Can I get on the beach in \(String(localized: name)) right now?", city: city)
        return .result(dialog: dialog)
    }
}

/// "Hey Siri, which beach day is best with Beach Info".
struct BestBeachDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Which day is best?"
    static let description = IntentDescription("The week ahead graded for a beach day, in the outlook's words.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await AskService.ask("Which day this weekend is best?", city: nil)
        return .result(dialog: dialog)
    }
}

/// The phrases Siri listens for. Apple requires the app name in each one,
/// and free text cannot ride in a phrase, so the free-form intent asks its
/// follow-up question out loud.
struct BeachAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskBeachIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) about the beach",
                "Ask \(.applicationName) a question",
            ],
            shortTitle: "Ask about the beach",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
        AppShortcut(
            intent: BeachOpenNowIntent(),
            phrases: [
                "Is the beach open in \(\.$city) with \(.applicationName)",
                "Can I get on the beach in \(\.$city) with \(.applicationName)",
                "Are the \(\.$city) ramps open with \(.applicationName)",
                "\(.applicationName) is the beach open in \(\.$city)",
            ],
            shortTitle: "Is the beach open?",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: BestBeachDayIntent(),
            phrases: [
                "Which beach day is best with \(.applicationName)",
                "\(.applicationName) which day is best this weekend",
                "When should I go to the beach with \(.applicationName)",
            ],
            shortTitle: "Which day is best?",
            systemImageName: "sun.max"
        )
    }
}
