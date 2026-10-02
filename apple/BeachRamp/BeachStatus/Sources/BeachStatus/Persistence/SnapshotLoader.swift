import Foundation

/// The widget extensions' data path (iOS and watchOS): the App Group
/// snapshot first, the network as fallback. Each platform has its own App
/// Group container — the phone and the watch never share a file — so each
/// app writes its own snapshot and its widgets read it.
public enum SnapshotLoader {
    /// The stored snapshot, or one fetch when there is none yet (fresh
    /// install, app never opened). Never refreshes a stored snapshot.
    public static func cachedOrFetched(api: APIClient = .shared) async -> BoardSnapshot? {
        if let cached = SnapshotStore.load() {
            return cached
        }
        async let ramps = try? api.fetchRamps()
        async let tide = try? api.fetchTides()
        async let chart = try? api.fetchTideChart()
        async let outlook = try? api.fetchOutlook()
        guard let ramps = await ramps else { return nil }
        return BoardSnapshot(ramps: ramps, tide: await tide, tideChart: await chart,
                             weather: nil, outlook: await outlook, fetchedAt: Date())
    }

    /// The snapshot refreshed over the network once it has aged past
    /// `maxAge`, and saved; the stale snapshot is still returned on network
    /// failure.
    public static func fresh(maxAge: TimeInterval = 120,
                             api: APIClient = .shared) async -> BoardSnapshot? {
        let cached = SnapshotStore.load()
        if let cached, cached.age() < maxAge {
            return cached
        }
        async let rampsTask = try? api.fetchRamps()
        async let tideTask = try? api.fetchTides()
        async let chartTask = try? api.fetchTideChart()
        async let outlookTask = try? api.fetchOutlook()
        if let ramps = await rampsTask {
            let fresh = BoardSnapshot(ramps: ramps, tide: await tideTask ?? cached?.tide,
                                      tideChart: await chartTask ?? cached?.tideChart,
                                      weather: cached?.weather,
                                      outlook: await outlookTask ?? cached?.outlook,
                                      fetchedAt: Date())
            SnapshotStore.save(fresh)
            return fresh
        }
        return cached
    }
}
