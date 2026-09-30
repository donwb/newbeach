import Foundation

/// When the Home Screen widget should ask WidgetKit to refresh. WidgetKit
/// rations refreshes per day, so the plan spends them where a ramp can
/// actually change: every quarter hour while the beach is drivable (plus a
/// margin after the close, when evening highs still shut ramps), and then
/// a single refresh timed to the next morning's open. Overnight the widget
/// still gets entries for the moving sky — those cost nothing, the timeline
/// already holds them.
public struct WidgetRefreshPlan: Equatable, Sendable {
    /// Instants to render; the first is `now`.
    public let entryDates: [Date]
    /// When WidgetKit should request a new timeline.
    public let nextRefresh: Date
    /// True while the plan is in its frequent, drivable-hours mode.
    public let active: Bool

    /// Refresh interval while ramps can change.
    public static let activeInterval: TimeInterval = 15 * 60
    /// How long past the learned close the county still shuts ramps for an
    /// evening high (the outlook's evening reach is 2.5h; this errs longer).
    public static let afterCloseMargin: TimeInterval = 3 * 60 * 60
    /// The overnight refresh lands this far before the open so the first
    /// look of the morning is fresh.
    public static let beforeOpenMargin: TimeInterval = 10 * 60
    /// Fallback cadence when the schedule is unknown.
    public static let fallbackInterval: TimeInterval = 20 * 60
    /// Entry spacing for the sky while dormant.
    public static let dormantEntryInterval: TimeInterval = 30 * 60

    /// - Parameters:
    ///   - opensAt: the day's open from the outlook schedule; after the day's
    ///     close the outlook already reports the *next* open.
    ///   - closesAt: the day's learned close.
    public static func plan(now: Date, opensAt: Date?, closesAt: Date?) -> WidgetRefreshPlan {
        guard let opensAt, let closesAt else {
            return WidgetRefreshPlan(
                entryDates: stride(from: 0, through: fallbackInterval, by: 5 * 60).map { now.addingTimeInterval($0) },
                nextRefresh: now.addingTimeInterval(fallbackInterval),
                active: true
            )
        }

        let activeEnd = closesAt.addingTimeInterval(afterCloseMargin)
        let dormantUntil = opensAt.addingTimeInterval(-beforeOpenMargin)

        // Drivable hours (and the evening margin): frequent.
        if now >= dormantUntil && now < activeEnd {
            return WidgetRefreshPlan(
                entryDates: stride(from: 0, through: activeInterval, by: 5 * 60).map { now.addingTimeInterval($0) },
                nextRefresh: now.addingTimeInterval(activeInterval),
                active: true
            )
        }

        // Before the open (overnight): one refresh just ahead of it, sky
        // entries in between. A schedule that is somehow behind us falls
        // back to the frequent cadence rather than sleeping forever.
        guard dormantUntil > now else {
            return WidgetRefreshPlan(
                entryDates: stride(from: 0, through: fallbackInterval, by: 5 * 60).map { now.addingTimeInterval($0) },
                nextRefresh: now.addingTimeInterval(fallbackInterval),
                active: true
            )
        }
        var dates: [Date] = []
        var t = now
        while t < dormantUntil && dates.count < 48 {
            dates.append(t)
            t = t.addingTimeInterval(dormantEntryInterval)
        }
        return WidgetRefreshPlan(entryDates: dates, nextRefresh: dormantUntil, active: false)
    }
}
