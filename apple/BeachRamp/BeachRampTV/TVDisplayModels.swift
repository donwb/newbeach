import SwiftUI
import BeachStatus

// Plain display structs assembled in ContentView so the band views stay dumb
// and previews stay trivial. Every prediction string in here is server copy
// rendered verbatim.

/// Focus identity for the whole screen — one enum instead of scattered
/// FocusStates, so surface open/close can stash and restore a single value.
enum RootFocus: Hashable {
    case outlookButton
    case cam(String)     // camera id
    case rampsHeader     // "RAMPS ‹ City ›"
    case ramp(String)    // ramp accessID
    case surface         // the open pull surface's hidden focus owner
}

/// Which pull surface is replacing the ledger. The header and the picture
/// never move; these swap the bottom 630pt only.
enum TVSurface: Equatable {
    case outlook
    case rampDetail(Ramp)

    static func == (lhs: TVSurface, rhs: TVSurface) -> Bool {
        switch (lhs, rhs) {
        case (.outlook, .outlook): true
        case let (.rampDetail(a), .rampDetail(b)): a.accessID == b.accessID
        default: false
        }
    }
}

/// One cell of the header's sun/weather display. A cell with a `symbol`
/// (SF Symbol name) draws the glyph in place of the text label — the
/// sunrise/sunset pair.
struct WeatherCell: Identifiable, Equatable {
    let label: String
    let value: String
    var symbol: String?
    var id: String { label }
}

/// The verdict row: an accent bar and two lines of server copy.
struct TVVerdictModel: Equatable {
    let headline: String
    let detail: String
    let barColor: Color
}

/// One ramp row in the ledger: Ramp / Now / Next.
struct TVRampRowModel: Identifiable, Equatable {
    let id: String       // accessID
    let name: String
    let nowLabel: String
    let isClosed: Bool
    /// The ramp's own predicted change — `RampOutlook.short` or the reopen
    /// label, verbatim. Nil renders an em dash.
    let nextLabel: String?
}

/// The surf block: window label ("Now"), the report line verbatim, facts.
struct TVSurfBoxModel: Equatable {
    let windowLabel: String
    let headline: String
    let detail: String
    let hasRead: Bool
}

/// One weekend day slot in the right box.
struct TVWeekendSlot: Identifiable, Equatable {
    let id: String       // server date label
    let dayName: String
    let headline: String
    let metrics: String
}

/// One row of the Beach outlook table.
struct TVOutlookDayRow: Identifiable, Equatable {
    let id: String       // server date label
    let day: String
    let high: String
    let rain: String
    let surf: String
    let bestWindow: String
    let closureRisk: String
    let isToday: Bool
    let isWorstRisk: Bool
}
