import Foundation

/// Reads and writes `BoardSnapshot` in the shared App Group container.
/// Deliberately dumb: one JSON file, atomic writes, no migration story —
/// a corrupt or missing snapshot just means the widget fetches.
public enum SnapshotStore {
    /// The App Group shared by the app and the widget extension.
    public static let appGroupID = "group.com.donwb.BeachRampTV"

    /// Favorites live here too so the board and the widget agree.
    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static let fileName = "board-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    public static func save(_ snapshot: BoardSnapshot) {
        guard let url = fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // Snapshot persistence is best-effort; the widget falls back to
            // fetching. Never let it interfere with the app's own load path.
        }
    }

    public static func load() -> BoardSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BoardSnapshot.self, from: data)
    }
}
