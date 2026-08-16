import WidgetKit
import SwiftUI
import BeachStatus

struct BoardEntry: TimelineEntry {
    let date: Date
    let cityName: String
    /// City ramps in board order, already narrowed by the Show mode.
    let ramps: [Ramp]
    /// The one ramp, when the widget is in One Ramp mode.
    let soloRamp: Ramp?
    let tide: TideInfo?
    let tideChart: TideChartData?
    let outlook: Outlook?
    let stale: Bool

    /// Ground state baked per entry — sun math needs no network, so the sky
    /// stays right even when the fetch is skipped.
    var ground: GroundState { GroundState.compute(at: date) }

    var verdict: Verdict {
        if let soloRamp {
            let others = ramps.filter { $0.accessID != soloRamp.accessID && $0.category == .open }
            let solo = VerdictBuilder.build(ramps: [soloRamp], tide: tide, sunset: nil,
                                            now: date, dataAge: stale ? 9999 : nil)
            _ = others
            return solo
        }
        return VerdictBuilder.build(ramps: ramps, tide: tide, sunset: nil,
                                    now: date, dataAge: stale ? 9999 : nil)
    }

    var openCount: Int { ramps.filter { $0.category == .open }.count }

    // MARK: Server prediction hints

    /// Flagged (possible/likely) drivable ramps with their outlook entries,
    /// most urgent first: likely beats possible, earlier window breaks ties.
    private var flaggedOutlooks: [(ramp: Ramp, entry: RampOutlook)] {
        guard let outlook else { return [] }
        return ramps.compactMap { ramp in
            guard ramp.category != .closed,
                  let ro = outlook.ramp(for: ramp.accessID),
                  ro.flagsRisk, ro.short != nil else { return nil }
            return (ramp, ro)
        }
        .sorted { a, b in
            if (a.entry.risk == "likely") != (b.entry.risk == "likely") {
                return a.entry.risk == "likely"
            }
            return (a.entry.window?.start ?? .distantFuture)
                < (b.entry.window?.start ?? .distantFuture)
        }
    }

    /// One-line hint for the medium/large families. The prediction string is
    /// always the server's own; only the name prefix and the count are
    /// composed here. Solo mode uses the solo ramp's hint alone.
    var outlookHintLine: String? {
        if let soloRamp {
            guard soloRamp.category != .closed,
                  let ro = outlook?.ramp(for: soloRamp.accessID),
                  ro.flagsRisk else { return nil }
            return ro.short
        }
        guard let best = flaggedOutlooks.first, let short = best.entry.short else { return nil }
        if flaggedOutlooks.count == 1 {
            return "\(best.ramp.shortDisplayName): \(short)"
        }
        return "Tide risk on \(flaggedOutlooks.count) ramps · \(short)"
    }

    /// Compact hint for the small family and Lock Screen: the server string
    /// alone for a single flagged ramp, a count line otherwise.
    var outlookCompactLine: String? {
        if let soloRamp {
            guard soloRamp.category != .closed,
                  let ro = outlook?.ramp(for: soloRamp.accessID),
                  ro.flagsRisk else { return nil }
            return ro.short
        }
        guard let best = flaggedOutlooks.first, let short = best.entry.short else { return nil }
        return flaggedOutlooks.count == 1 ? short : "tide risk on \(flaggedOutlooks.count) ramps"
    }
}

struct BoardTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: .now, cityName: "New Smyrna Beach",
                   ramps: BoardEntry.sampleRamps, soloRamp: nil,
                   tide: nil, tideChart: nil, outlook: nil, stale: false)
    }

    func snapshot(for configuration: RampWidgetIntent, in context: Context) async -> BoardEntry {
        await entry(for: configuration, at: .now, snapshot: WidgetData.snapshot())
    }

    func timeline(for configuration: RampWidgetIntent, in context: Context) async -> Timeline<BoardEntry> {
        let snapshot = await WidgetData.freshSnapshot()
        // Entries every 15 minutes for an hour: the sun moves even when the
        // data doesn't, and WidgetKit re-requests at the end.
        let entries = stride(from: 0, through: 60, by: 15).map { minutes in
            entry(for: configuration,
                  at: Date().addingTimeInterval(TimeInterval(minutes * 60)),
                  snapshot: snapshot)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(for configuration: RampWidgetIntent, at date: Date,
                       snapshot: BoardSnapshot?) -> BoardEntry {
        let city = configuration.city?.id ?? "New Smyrna Beach"
        let all = (snapshot?.ramps ?? []).filter { $0.cityDisplay == city }.boardOrdered()

        var ramps = all
        var solo: Ramp?
        switch configuration.show {
        case .allRamps:
            break
        case .favoritesOnly:
            let favorites = WidgetData.favorites()
            let filtered = all.filter { favorites.contains($0.accessID) }
            if !filtered.isEmpty { ramps = filtered }
        case .oneRamp:
            solo = all.first { $0.accessID == configuration.ramp?.id } ?? all.first
        }

        let stale = (snapshot?.age(now: date) ?? .infinity) > 30 * 60
        return BoardEntry(date: date, cityName: city, ramps: ramps, soloRamp: solo,
                          tide: snapshot?.tide, tideChart: snapshot?.tideChart,
                          outlook: snapshot?.outlook,
                          stale: stale && snapshot != nil)
    }
}

extension BoardEntry {
    /// Redacted-placeholder data so the gallery shows the real shape.
    static var sampleRamps: [Ramp] {
        let names = ["BEACHWAY AV", "CRAWFORD RD", "FLAGLER AV", "3RD AV", "27TH AV"]
        return names.enumerated().map { index, name in
            Ramp(id: index, rampName: name,
                 accessStatus: index == 0 ? "OPEN - ENTRANCE ONLY" : "OPEN",
                 statusCategory: index == 0 ? "limited" : "open",
                 objectID: index, city: "NEW SMYRNA BEACH", accessID: "NS-\(index)",
                 location: "", lastUpdated: nil, statusSince: nil,
                 sortOrder: index + 1)
        }
    }
}
