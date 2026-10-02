import Foundation

/// Which ramps the watch widget card shows: four circles fit, so a city has
/// to be narrowed. Ramps pinned in the watch app come first (pin order),
/// then the city's driver order fills the rest — so a fresh install still
/// shows a sensible four (NSB: Beachway, Crawford, Flagler, 3rd) and pinning
/// only ever swaps in the ramps you care about.
public enum WatchRampPicks {
    /// Circles on the rectangular card.
    public static let limit = 4

    /// App Group key for the pinned ramp ids, oldest pin first.
    public static let defaultsKey = "watchWidgetRampIDs"

    /// The ramps to show for `city` (title-cased, as `Ramp.cityDisplay`).
    public static func ramps(in city: String, from all: [Ramp], pinned: [String],
                             limit: Int = limit) -> [Ramp] {
        let cityRamps = all.filter { $0.cityDisplay == city }.boardOrdered()
        let byID = Dictionary(cityRamps.map { ($0.accessID, $0) }, uniquingKeysWith: { a, _ in a })
        var picked = pinned.compactMap { byID[$0] }
        var seen = Set(picked.map(\.accessID))
        picked = Array(picked.prefix(limit))
        for ramp in cityRamps where picked.count < limit && !seen.contains(ramp.accessID) {
            picked.append(ramp)
            seen.insert(ramp.accessID)
        }
        // Pins sit in board order on the card, so the circles read
        // north-to-south like every other surface.
        let order = Dictionary(cityRamps.enumerated().map { ($1.accessID, $0) },
                               uniquingKeysWith: { a, _ in a })
        return picked.sorted { (order[$0.accessID] ?? .max) < (order[$1.accessID] ?? .max) }
    }

    /// Toggles a pin. A city holds at most `limit` pins; pinning a fifth
    /// drops that city's oldest so the newest choice always shows.
    public static func toggling(_ accessID: String, in pinned: [String],
                                all: [Ramp], limit: Int = limit) -> [String] {
        if pinned.contains(accessID) {
            return pinned.filter { $0 != accessID }
        }
        var result = pinned
        let city = all.first { $0.accessID == accessID }?.cityDisplay
        let sameCity = result.filter { id in all.first { $0.accessID == id }?.cityDisplay == city }
        if city != nil, sameCity.count >= limit, let oldest = sameCity.first {
            result.removeAll { $0 == oldest }
        }
        result.append(accessID)
        return result
    }

    /// Pinned ids from the watch's App Group.
    public static func load() -> [String] {
        SnapshotStore.sharedDefaults?.stringArray(forKey: defaultsKey) ?? []
    }

    public static func save(_ pinned: [String]) {
        SnapshotStore.sharedDefaults?.set(pinned, forKey: defaultsKey)
    }
}
