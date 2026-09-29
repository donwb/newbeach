import AppIntents
import BeachStatus

// Ramps as a Siri parameter, so "Hey Siri, is Flagler Avenue open with Beach
// Info" is a one-shot phrase like the city one. Siri can only fill a phrase
// slot from values it has been told about, so the roster is exposed as an
// AppEntity (from the board snapshot the app keeps for its widgets, or one
// fetch on a fresh install) and re-registered at every launch.

/// One ramp, named the way it is said aloud ("Flagler Avenue", not "Flagler Av").
struct AskRampEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ramp")
    static let defaultQuery = AskRampQuery()

    /// County access id (NS-110).
    var id: String
    var spokenName: String
    var city: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(spokenName)", subtitle: "\(city)")
    }

    init(ramp: Ramp) {
        id = ramp.accessID
        spokenName = AskRampEntity.spoken(ramp.rampDisplayName)
        city = ramp.cityDisplay
    }

    /// "Flagler Av" → "Flagler Avenue"; the abbreviations the county uses,
    /// expanded so Siri's speech matching has the words people say.
    static func spoken(_ display: String) -> String {
        let map: [String: String] = [
            "Av": "Avenue", "Ave": "Avenue", "Blvd": "Boulevard", "Rd": "Road",
            "Dr": "Drive", "St": "Street", "Ln": "Lane", "Ct": "Court",
        ]
        return display.split(separator: " ").map { part in
            map[String(part)] ?? String(part)
        }.joined(separator: " ")
    }

    struct AskRampQuery: EntityQuery {
        func entities(for identifiers: [String]) async throws -> [AskRampEntity] {
            let ramps = await AskRampEntity.roster()
            return identifiers.compactMap { id in
                ramps.first { $0.accessID == id }.map(AskRampEntity.init(ramp:))
            }
        }

        func suggestedEntities() async throws -> [AskRampEntity] {
            await AskRampEntity.roster().map(AskRampEntity.init(ramp:))
        }
    }

    /// The roster: the widget snapshot first (instant), the network otherwise.
    static func roster() async -> [Ramp] {
        if let cached = SnapshotStore.load()?.ramps, !cached.isEmpty {
            return cached
        }
        return (try? await APIClient.shared.fetchRamps()) ?? []
    }
}

/// One-shot: "Hey Siri, is Flagler Avenue open with Beach Info".
struct RampOpenNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Is a ramp open?"
    static let description = IntentDescription("Whether one beach access ramp is open right now, and the outlook for it.")
    static let openAppWhenRun = false

    @Parameter(title: "Ramp", requestValueDialog: "Which ramp?")
    var ramp: AskRampEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Is \(\.$ramp) open?")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The server's quick path resolves the ramp from its name and
        // answers from the live board, no model.
        let dialog = try await AskService.ask("Is \(ramp.spokenName) open right now?", city: nil, accessID: ramp.id)
        return .result(dialog: dialog)
    }
}
