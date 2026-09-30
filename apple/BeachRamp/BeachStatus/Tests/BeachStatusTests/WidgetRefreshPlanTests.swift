import Foundation
import Testing
@testable import BeachStatus

struct WidgetRefreshPlanTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func et(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute))!
    }

    @Test func drivableHoursRefreshEveryQuarterHour() {
        let plan = WidgetRefreshPlan.plan(now: et(10, 14), opensAt: et(10, 8), closesAt: et(10, 18, 30))
        #expect(plan.active)
        #expect(plan.nextRefresh == et(10, 14, 15))
        #expect(plan.entryDates.first == et(10, 14))
        #expect(plan.entryDates.count == 4, "5-minute sky entries across the quarter hour")
    }

    @Test func eveningMarginStaysFrequent() {
        // 8pm with a 6:30pm close: evening highs still close ramps.
        let plan = WidgetRefreshPlan.plan(now: et(10, 20), opensAt: et(10, 8), closesAt: et(10, 18, 30))
        #expect(plan.active)
        #expect(plan.nextRefresh == et(10, 20, 15))
    }

    @Test func overnightSleepsUntilJustBeforeTheOpen() {
        // After the close the outlook reports tomorrow's open.
        let plan = WidgetRefreshPlan.plan(now: et(10, 23), opensAt: et(11, 8), closesAt: et(11, 18, 30))
        #expect(!plan.active)
        #expect(plan.nextRefresh == et(11, 7, 50))
        #expect(plan.entryDates.first == et(10, 23))
        #expect(plan.entryDates.count == 18, "half-hour sky entries across the night")
        #expect(plan.entryDates.last! < plan.nextRefresh)
    }

    @Test func justBeforeTheOpenIsAlreadyActive() {
        let plan = WidgetRefreshPlan.plan(now: et(11, 7, 55), opensAt: et(11, 8), closesAt: et(11, 18, 30))
        #expect(plan.active)
        #expect(plan.nextRefresh == et(11, 8, 10))
    }

    @Test func unknownScheduleFallsBack() {
        let plan = WidgetRefreshPlan.plan(now: et(10, 14), opensAt: nil, closesAt: nil)
        #expect(plan.active)
        #expect(plan.nextRefresh == et(10, 14, 20))
    }

    @Test func staleScheduleNeverSleepsForever() {
        // A schedule entirely in the past (bad cache): frequent, not dormant.
        let plan = WidgetRefreshPlan.plan(now: et(12, 14), opensAt: et(10, 8), closesAt: et(10, 18, 30))
        #expect(plan.active)
        #expect(plan.nextRefresh == et(12, 14, 20))
    }
}
