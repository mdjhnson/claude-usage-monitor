import XCTest
@testable import PaceBarCore

final class CoolingDateTests: XCTestCase {
    func testCalendarModeSession() {
        let now = ny(2026, 6, 10, 12)
        // Expected 50, actual 70: delta 20% of 5h = 1h.
        let r = PacingCalculator.calculate(
            utilization: 70, resetsAt: now.addingTimeInterval(2.5 * hour), kind: .session, now: now, calendar: newYork
        )
        XCTAssertEqual(r.coolingDate, now.addingTimeInterval(hour))
    }

    func testCalendarModeWeekly() {
        // Window Sat Jun 6 to Sat Jun 13; Tue noon = 50%; actual 60 -> 10% of 7d = 16.8h.
        let now = ny(2026, 6, 9, 12)
        let r = PacingCalculator.calculate(utilization: 60, resetsAt: ny(2026, 6, 13), kind: .weekly, now: now, calendar: newYork)
        XCTAssertEqual(r.coolingDate!.timeIntervalSince(now), 16.8 * hour, accuracy: 1e-6)
    }

    func testNoCoolingWhenUnderPace() {
        let now = ny(2026, 6, 10, 12)
        let r = PacingCalculator.calculate(
            utilization: 50, resetsAt: now.addingTimeInterval(2.5 * hour), kind: .session, now: now, calendar: newYork
        )
        XCTAssertNil(r.coolingDate)
    }

    func testCalendarModeNeverExceedsReset() {
        let now = ny(2026, 6, 10, 12)
        let reset = now.addingTimeInterval(0.5 * hour) // 90% elapsed
        let r = PacingCalculator.calculate(utilization: 120, resetsAt: reset, kind: .session, now: now, calendar: newYork)
        XCTAssertEqual(r.coolingDate, reset)
    }

    func testScheduleModeLandsAfterWeekend() {
        // Window Wed Jun 3 to Wed Jun 10, Mon-Fri active: 120h total.
        // Fri Jun 5 12:00: Wed + Thu + 12h = 60h -> expected 50. Actual 65 -> delta 15 -> 18h needed.
        // 12h remain on Friday, the weekend is skipped, 6h more lands Monday 06:00.
        let r = PacingCalculator.calculate(
            utilization: 65, resetsAt: ny(2026, 6, 10), kind: .weekly, schedule: schedule(),
            now: ny(2026, 6, 5, 12), calendar: newYork
        )
        XCTAssertEqual(r.expectedUsage, 50, accuracy: 1e-9)
        XCTAssertEqual(r.coolingDate, ny(2026, 6, 8, 6))
    }

    func testScheduleModeStartingInOffTime() {
        // Saturday noon in the same window: nothing active until Monday 00:00.
        // Expected = Wed+Thu+Fri = 72h/120h = 60. Actual 66 -> delta 6 -> 7.2h -> Mon 07:12.
        let r = PacingCalculator.calculate(
            utilization: 66, resetsAt: ny(2026, 6, 10), kind: .weekly, schedule: schedule(),
            now: ny(2026, 6, 6, 12), calendar: newYork
        )
        XCTAssertEqual(r.expectedUsage, 60, accuracy: 1e-9)
        XCTAssertEqual(r.coolingDate!.timeIntervalSince(ny(2026, 6, 8)), 7.2 * hour, accuracy: 1e-6)
        XCTAssertTrue(r.isOffTime)
    }

    func testScheduleModeWithHoursLandsNextMorning() {
        // Window Sat Jun 6 to Sat Jun 13, Mon-Fri 9-18 (45h). Mon 17:00 = 8h -> expected 17.78.
        // Actual such that delta = 20% of 45h = 9h: 1h left Monday, then 8h Tuesday -> Tue 17:00.
        let now = ny(2026, 6, 8, 17)
        let expected = 8.0 / 45 * 100
        let r = PacingCalculator.calculate(
            utilization: expected + 20, resetsAt: ny(2026, 6, 13), kind: .weekly, schedule: schedule(hours: (9, 18)),
            now: now, calendar: newYork
        )
        XCTAssertEqual(r.coolingDate!.timeIntervalSince(ny(2026, 6, 9, 17)), 0, accuracy: 1e-3)
    }

    func testScheduleModeNeverExceedsReset() {
        // Thu Jun 11 noon in a Mon-Fri week ending Sat: 1.5 active days remain (36h of 120h = 30%).
        // A 50% delta needs 60h, more than remains, so the result is the reset.
        let r = PacingCalculator.calculate(
            utilization: 120, resetsAt: ny(2026, 6, 13), kind: .weekly, schedule: schedule(),
            now: ny(2026, 6, 11, 12), calendar: newYork
        )
        XCTAssertEqual(r.coolingDate, ny(2026, 6, 13))
    }
}
