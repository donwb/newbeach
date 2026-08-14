import Foundation
import Testing
@testable import BeachStatus

struct SinceFormatterTests {
    private static let eastern = TimeZone(identifier: "America/New_York")!

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: Self.eastern,
            year: 2026, month: month, day: day, hour: hour, minute: minute
        ).date!
    }

    @Test func todayShowsClockTime() {
        let now = date(8, 14, 13, 30)
        #expect(SinceFormatter.string(from: date(8, 14, 6, 2), now: now) == "6:02 AM")
        #expect(SinceFormatter.string(from: date(8, 14, 12, 48), now: now) == "12:48 PM")
    }

    @Test func yesterdayIsPrefixed() {
        let now = date(8, 14, 13, 30)
        #expect(SinceFormatter.string(from: date(8, 13, 16, 11), now: now) == "Yest 4:11 PM")
    }

    @Test func olderShowsMonthDay() {
        let now = date(8, 14, 13, 30)
        #expect(SinceFormatter.string(from: date(6, 8, 9, 0), now: now) == "Jun 8")
    }

    /// Late-night boundary: 11:50 PM yesterday vs 00:10 today.
    @Test func dayBoundary() {
        let now = date(8, 14, 0, 10)
        #expect(SinceFormatter.string(from: date(8, 13, 23, 50), now: now) == "Yest 11:50 PM")
        #expect(SinceFormatter.string(from: date(8, 14, 0, 5), now: now) == "12:05 AM")
    }
}
