import Foundation
import Observation
import WidgetKit
import BeachStatus

/// View model for the watchOS app — ramps only, optimized for quick glances.
@Observable
final class WatchViewModel {
    var ramps: [Ramp] = []
    var config: AppConfig?
    var isLoading = false
    var errorMessage: String?

    /// Show NSB ramps by default, with ability to see all.
    var showAllCities = false

    /// Ramps pinned to the watch widget card (`WatchRampPicks`).
    var pinnedIDs: [String] = WatchRampPicks.load()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// NSB ramps (default glance view).
    var nsbRamps: [Ramp] {
        ramps.filter { $0.cityDisplay == defaultCity }.boardOrdered()
    }

    /// Ramps currently displayed based on filter.
    var displayedRamps: [Ramp] {
        showAllCities ? ramps : nsbRamps
    }

    var openCount: Int { displayedRamps.filter { $0.category == .open }.count }
    var limitedCount: Int { displayedRamps.filter { $0.category == .limited }.count }
    var closedCount: Int { displayedRamps.filter { $0.category == .closed }.count }
    var totalCount: Int { displayedRamps.count }

    /// Default city from config or fallback.
    var defaultCity: String {
        config.map { $0.defaultCity.titleCased } ?? "New Smyrna Beach"
    }

    /// Unique city names.
    var cities: [String] {
        Array(Set(ramps.map(\.cityDisplay))).sorted()
    }

    @MainActor
    func loadAll() async {
        isLoading = true
        errorMessage = nil

        async let rampsResult: () = loadRamps()
        async let configResult: () = loadConfig()
        _ = await (rampsResult, configResult)

        isLoading = false
    }

    @MainActor
    func refresh() async {
        await loadAll()
    }

    func isPinned(_ ramp: Ramp) -> Bool {
        pinnedIDs.contains(ramp.accessID)
    }

    @MainActor
    func togglePin(_ ramp: Ramp) {
        pinnedIDs = WatchRampPicks.toggling(ramp.accessID, in: pinnedIDs, all: ramps)
        WatchRampPicks.save(pinnedIDs)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Ramps come through the shared snapshot so the watch widget reads
    /// exactly what the app just showed (and the outlook schedule that
    /// paces its refreshes).
    @MainActor
    private func loadRamps() async {
        if let snapshot = await SnapshotLoader.fresh(maxAge: 60, api: api) {
            ramps = snapshot.ramps
            if snapshot.age() > 60 { errorMessage = "Failed to load ramps" }
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            errorMessage = "Failed to load ramps"
        }
    }

    @MainActor
    private func loadConfig() async {
        do {
            config = try await api.fetchConfig()
        } catch {
            // Non-critical
        }
    }
}
