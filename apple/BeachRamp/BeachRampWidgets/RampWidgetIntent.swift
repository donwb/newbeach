import AppIntents
import WidgetKit
import BeachStatus

/// Per-widget configuration: which city, and how much of it. Two widgets can
/// watch two cities.
struct RampWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Ramp Widget"
    static let description = IntentDescription("Ramp status for a city.")

    @Parameter(title: "City")
    var city: CityEntity?

    @Parameter(title: "Show", default: .allRamps)
    var show: ShowMode

    /// Only consulted when `show` is One Ramp — the widget becomes that
    /// ramp's own verdict and forward-looking line.
    @Parameter(title: "Ramp")
    var ramp: RampEntity?
}

enum ShowMode: String, AppEnum {
    case allRamps
    /// Ramps pinned from the app's detail screen ("Pin to widget"). The
    /// case name is historical — renaming it would break saved widget configs.
    case favoritesOnly
    case oneRamp

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Show")
    static let caseDisplayRepresentations: [ShowMode: DisplayRepresentation] = [
        .allRamps: "All ramps",
        .favoritesOnly: "Pinned ramps",
        .oneRamp: "One ramp",
    ]
}

struct CityEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "City")
    static let defaultQuery = CityQuery()

    /// Title-cased city name ("New Smyrna Beach").
    var id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }

    struct CityQuery: EntityQuery {
        func entities(for identifiers: [String]) async throws -> [CityEntity] {
            identifiers.map { CityEntity(id: $0) }
        }

        func suggestedEntities() async throws -> [CityEntity] {
            let ramps = await WidgetData.ramps()
            let cities = Array(Set(ramps.map(\.cityDisplay))).sorted()
            return cities.map { CityEntity(id: $0) }
        }

        func defaultResult() async -> CityEntity? {
            CityEntity(id: "New Smyrna Beach")
        }
    }
}

struct RampEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ramp")
    static let defaultQuery = RampQuery()

    /// County access id (NS-106).
    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    struct RampQuery: EntityQuery {
        func entities(for identifiers: [String]) async throws -> [RampEntity] {
            let ramps = await WidgetData.ramps()
            return identifiers.compactMap { id in
                ramps.first { $0.accessID == id }.map {
                    RampEntity(id: $0.accessID, name: $0.rampDisplayName)
                }
            }
        }

        func suggestedEntities() async throws -> [RampEntity] {
            await WidgetData.ramps().boardOrdered().map {
                RampEntity(id: $0.accessID, name: "\($0.rampDisplayName) · \($0.cityDisplay)")
            }
        }
    }
}

/// Shared data access for the provider and the intent queries: the App Group
/// snapshot first (instant), the network as fallback.
enum WidgetData {
    static func snapshot() async -> BoardSnapshot? {
        if let cached = SnapshotStore.load() {
            return cached
        }
        // No snapshot (fresh install, app never opened) — fetch once.
        async let ramps = try? APIClient.shared.fetchRamps()
        async let tide = try? APIClient.shared.fetchTides()
        async let chart = try? APIClient.shared.fetchTideChart()
        async let outlook = try? APIClient.shared.fetchOutlook()
        guard let ramps = await ramps else { return nil }
        return BoardSnapshot(ramps: ramps, tide: await tide, tideChart: await chart,
                             weather: nil, outlook: await outlook, fetchedAt: Date())
    }

    /// Snapshot refreshed over the network when it has aged past the poll
    /// cycle; the stale snapshot is still returned on network failure.
    static func freshSnapshot() async -> BoardSnapshot? {
        let cached = SnapshotStore.load()
        if let cached, cached.age() < 120 {
            return cached
        }
        async let rampsTask = try? APIClient.shared.fetchRamps()
        async let tideTask = try? APIClient.shared.fetchTides()
        async let chartTask = try? APIClient.shared.fetchTideChart()
        async let outlookTask = try? APIClient.shared.fetchOutlook()
        if let ramps = await rampsTask {
            let fresh = BoardSnapshot(ramps: ramps, tide: await tideTask,
                                      tideChart: await chartTask,
                                      weather: cached?.weather,
                                      outlook: await outlookTask ?? cached?.outlook,
                                      fetchedAt: Date())
            SnapshotStore.save(fresh)
            return fresh
        }
        return cached
    }

    static func ramps() async -> [Ramp] {
        await snapshot()?.ramps ?? []
    }

    /// Pinned ramp ids; the key name is historical.
    static func favorites() -> Set<String> {
        Set(SnapshotStore.sharedDefaults?.stringArray(forKey: "favoriteRampIDs") ?? [])
    }
}
