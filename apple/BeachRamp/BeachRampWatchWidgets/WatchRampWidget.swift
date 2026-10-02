import AppIntents
import SwiftUI
import WidgetKit
import BeachStatus

@main
struct BeachRampWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchRampWidget()
    }
}

/// Smart Stack card and watch-face complications for one city. The card
/// shows four ramp circles — the watch app's pins first, then driver order
/// (`WatchRampPicks`); the round and inline faces show the city's count.
struct WatchRampWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "WatchRampWidget",
            intent: WatchRampWidgetIntent.self,
            provider: WatchRampProvider()
        ) { entry in
            WatchRampWidgetView(entry: entry)
        }
        .configurationDisplayName("Ramps")
        .description("Four ramps in your city at a glance.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular,
                            .accessoryCorner, .accessoryInline])
    }
}

// MARK: - Configuration

struct WatchRampWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Ramps"
    static let description = IntentDescription("Ramp status for a city.")

    @Parameter(title: "City")
    var city: WatchCityEntity?

    init() {}

    init(city: String) {
        self.city = WatchCityEntity(id: city)
    }
}

struct WatchCityEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "City")
    static let defaultQuery = Query()

    /// Title-cased city name ("New Smyrna Beach").
    var id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }

    struct Query: EntityQuery {
        func entities(for identifiers: [String]) async throws -> [WatchCityEntity] {
            identifiers.map { WatchCityEntity(id: $0) }
        }

        func suggestedEntities() async throws -> [WatchCityEntity] {
            await WatchRampProvider.cities().map { WatchCityEntity(id: $0) }
        }

        func defaultResult() async -> WatchCityEntity? {
            WatchCityEntity(id: WatchRampProvider.defaultCity)
        }
    }
}

// MARK: - Timeline

struct WatchRampEntry: TimelineEntry {
    let date: Date
    let city: String
    /// Every ramp in the city, for the counts.
    let cityRamps: [Ramp]
    /// The card's circles (≤ 4).
    let picks: [Ramp]
    let stale: Bool

    var openCount: Int { cityRamps.filter { $0.category == .open }.count }
}

struct WatchRampProvider: AppIntentTimelineProvider {
    nonisolated static let defaultCity = "New Smyrna Beach"

    func placeholder(in context: Context) -> WatchRampEntry {
        Self.entry(city: Self.defaultCity, at: .now, ramps: WatchRampEntry.sampleRamps,
                   fetchedAt: .now)
    }

    func snapshot(for configuration: WatchRampWidgetIntent, in context: Context) async -> WatchRampEntry {
        let snapshot = await SnapshotLoader.cachedOrFetched()
        let ramps = snapshot?.ramps ?? (context.isPreview ? WatchRampEntry.sampleRamps : [])
        return Self.entry(city: city(configuration), at: .now, ramps: ramps,
                          fetchedAt: snapshot?.fetchedAt ?? .now)
    }

    func timeline(for configuration: WatchRampWidgetIntent, in context: Context) async -> Timeline<WatchRampEntry> {
        let snapshot = await SnapshotLoader.fresh(maxAge: 120)
        // The same refresh budget plan as the iPhone widget: quarter-hourly
        // through the driving day, one refresh before the next open.
        let plan = WidgetRefreshPlan.plan(
            now: Date(),
            opensAt: snapshot?.outlook?.schedule.opensAt,
            closesAt: snapshot?.outlook?.schedule.closesAt
        )
        let entries = plan.entryDates.map { date in
            Self.entry(city: city(configuration), at: date, ramps: snapshot?.ramps ?? [],
                       fetchedAt: snapshot?.fetchedAt)
        }
        return Timeline(entries: entries, policy: .after(plan.nextRefresh))
    }

    /// The Smart Stack has no configuration screen, so each city is offered
    /// as its own ready-made widget; the default city leads.
    func recommendations() -> [AppIntentRecommendation<WatchRampWidgetIntent>] {
        let cities = (SnapshotStore.load()?.ramps).map(Self.cities(from:)) ?? [Self.defaultCity]
        return cities.map { city in
            AppIntentRecommendation(intent: WatchRampWidgetIntent(city: city), description: city)
        }
    }

    private func city(_ configuration: WatchRampWidgetIntent) -> String {
        configuration.city?.id ?? Self.defaultCity
    }

    private static func entry(city: String, at date: Date, ramps: [Ramp],
                              fetchedAt: Date?) -> WatchRampEntry {
        let cityRamps = ramps.filter { $0.cityDisplay == city }
        let picks = WatchRampPicks.ramps(in: city, from: ramps, pinned: WatchRampPicks.load())
        let stale = fetchedAt.map { date.timeIntervalSince($0) > 30 * 60 } ?? false
        return WatchRampEntry(date: date, city: city, cityRamps: cityRamps, picks: picks,
                              stale: stale)
    }

    static func cities() async -> [String] {
        cities(from: await SnapshotLoader.cachedOrFetched()?.ramps ?? [])
    }

    /// Cities with the default first, the rest alphabetical.
    static func cities(from ramps: [Ramp]) -> [String] {
        let all = Set(ramps.map(\.cityDisplay)).union([defaultCity])
        return [defaultCity] + all.subtracting([defaultCity]).sorted()
    }
}

extension WatchRampEntry {
    static var sampleRamps: [Ramp] {
        let rows: [(String, String, String)] = [
            ("BEACHWAY AV", "OPEN", "open"),
            ("CRAWFORD RD", "OPEN - ENTRANCE ONLY", "limited"),
            ("FLAGLER AV", "OPEN", "open"),
            ("3RD AV", "CLOSED FOR HIGH TIDE", "closed"),
            ("27TH AV", "OPEN", "open"),
        ]
        return rows.enumerated().map { index, row in
            Ramp(id: index, rampName: row.0, accessStatus: row.1, statusCategory: row.2,
                 objectID: index, city: "NEW SMYRNA BEACH", accessID: "NS-\(index)",
                 location: "", lastUpdated: nil, sortOrder: index + 1)
        }
    }
}
