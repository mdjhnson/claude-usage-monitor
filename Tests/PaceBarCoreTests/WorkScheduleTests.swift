import XCTest
@testable import PaceBarCore

final class WorkScheduleTests: XCTestCase {
    // Sat Jun 6 2026 to Sat Jun 13 2026, no DST change.
    let weekStart = ny(2026, 6, 6)
    let weekEnd = ny(2026, 6, 13)

    func testWeekendExclusion() {
        let s = schedule()
        XCTAssertEqual(s.activeSeconds(from: weekStart, to: weekEnd, calendar: newYork), 5 * day)

        // Monday 00:00: the whole weekend has passed but no active time has.
        let monday = PacingCalculator.calculate(
            utilization: 10, resetsAt: weekEnd, kind: .weekly, schedule: s, now: ny(2026, 6, 8), calendar: newYork
        )
        XCTAssertEqual(monday.expectedUsage, 0, accuracy: 1e-9)

        // Wednesday noon: Mon + Tue + 12h = 60h of 120h.
        let wednesday = PacingCalculator.calculate(
            utilization: 50, resetsAt: weekEnd, kind: .weekly, schedule: s, now: ny(2026, 6, 10, 12), calendar: newYork
        )
        XCTAssertEqual(wednesday.expectedUsage, 50, accuracy: 1e-9)
        XCTAssertEqual(wednesday.zone, .onTrack)
    }

    func testHoursWindow() {
        let s = schedule(hours: (9, 18))
        XCTAssertEqual(s.activeSeconds(from: weekStart, to: weekEnd, calendar: newYork), 45 * hour)

        // Mon 13:30 is 4.5h into 45h: 10%.
        let r = PacingCalculator.calculate(
            utilization: 10, resetsAt: weekEnd, kind: .weekly, schedule: s, now: ny(2026, 6, 8, 13, 30), calendar: newYork
        )
        XCTAssertEqual(r.expectedUsage, 10, accuracy: 1e-9)
        XCTAssertFalse(r.isOffTime)

        // Mon 20:00 is off time; expected pace holds at 9h of 45h.
        let evening = PacingCalculator.calculate(
            utilization: 10, resetsAt: weekEnd, kind: .weekly, schedule: s, now: ny(2026, 6, 8, 20), calendar: newYork
        )
        XCTAssertEqual(evening.expectedUsage, 20, accuracy: 1e-9)
        XCTAssertTrue(evening.isOffTime)
    }

    func testOffTimeRangesAndMarkerUseCalendarTime() {
        let r = PacingCalculator.calculate(
            utilization: 10, resetsAt: weekEnd, kind: .weekly, schedule: schedule(), now: ny(2026, 6, 8), calendar: newYork
        )
        // Sat + Sun = first 2/7 of the window are off.
        XCTAssertEqual(r.offTimeRanges.count, 1)
        XCTAssertEqual(r.offTimeRanges[0].lowerBound, 0, accuracy: 1e-9)
        XCTAssertEqual(r.offTimeRanges[0].upperBound, 2.0 / 7, accuracy: 1e-9)
        // The marker sits at calendar "now" (2/7), not at expected usage (0).
        XCTAssertEqual(r.markerFraction, 2.0 / 7, accuracy: 1e-9)
    }

    func testEndHour24IsMidnight() {
        let s = schedule(days: WorkSchedule.allDays, hours: (18, 24))
        XCTAssertTrue(s.isRestricting)
        let intervals = s.activeIntervals(from: ny(2026, 6, 8), to: ny(2026, 6, 9), calendar: newYork)
        XCTAssertEqual(intervals, [DateInterval(start: ny(2026, 6, 8, 18), end: ny(2026, 6, 9))])
        XCTAssertEqual(s.activeSeconds(from: weekStart, to: weekEnd, calendar: newYork), 7 * 6 * hour)
    }

    func testEmptyDaySetFallsBackToAllDays() {
        let empty = schedule(days: [])
        XCTAssertEqual(empty.effectiveDays, WorkSchedule.allDays)
        XCTAssertFalse(empty.isRestricting)
        XCTAssertEqual(empty.activeSeconds(from: weekStart, to: weekEnd, calendar: newYork), 7 * day)

        let r = PacingCalculator.calculate(
            utilization: 50, resetsAt: weekEnd, kind: .weekly, schedule: empty, now: ny(2026, 6, 9, 12), calendar: newYork
        )
        XCTAssertFalse(r.usesSchedule)
        XCTAssertEqual(r.expectedUsage, 50, accuracy: 1e-9)

        // With hours on, an empty day set still means every day within those hours.
        let emptyWithHours = schedule(days: [], hours: (9, 18))
        XCTAssertEqual(emptyWithHours.activeSeconds(from: weekStart, to: weekEnd, calendar: newYork), 7 * 9 * hour)
    }

    func testInvalidHourWindowIsIgnored() {
        let s = schedule(days: WorkSchedule.allDays, hours: (18, 9))
        XCTAssertNil(s.effectiveHours)
        XCTAssertFalse(s.isRestricting)
    }

    func testRangeWithNoActiveTime() {
        // Only Sunday is active; Mon 00:00 to Sun 00:00 contains none of it.
        let s = schedule(days: [1])
        XCTAssertEqual(s.activeSeconds(from: ny(2026, 6, 8), to: ny(2026, 6, 14), calendar: newYork), 0)
        XCTAssertTrue(s.activeIntervals(from: ny(2026, 6, 8), to: ny(2026, 6, 8), calendar: newYork).isEmpty)
        XCTAssertTrue(s.activeIntervals(from: ny(2026, 6, 9), to: ny(2026, 6, 8), calendar: newYork).isEmpty)
    }

    func testOutOfRangeHoursAreClamped() {
        let s = schedule(days: WorkSchedule.allDays, hours: (-3, 99))
        XCTAssertEqual(s.effectiveHours?.start, 0)
        XCTAssertEqual(s.effectiveHours?.end, 24)
        XCTAssertEqual(s.activeSeconds(from: ny(2026, 6, 8), to: ny(2026, 6, 9), calendar: newYork), day)
    }

    // MARK: DST

    func testSpringForwardDay() {
        // Sun Mar 8 2026: clocks jump 02:00 -> 03:00 in New York.
        let all = schedule(days: WorkSchedule.allDays)
        XCTAssertEqual(all.activeSeconds(from: ny(2026, 3, 8), to: ny(2026, 3, 9), calendar: newYork), 23 * hour)

        let fullDay = schedule(days: WorkSchedule.allDays, hours: (0, 24))
        XCTAssertEqual(fullDay.activeSeconds(from: ny(2026, 3, 8), to: ny(2026, 3, 9), calendar: newYork), 23 * hour)

        let workday = schedule(days: WorkSchedule.allDays, hours: (9, 18))
        XCTAssertEqual(workday.activeSeconds(from: ny(2026, 3, 8), to: ny(2026, 3, 9), calendar: newYork), 9 * hour)

        // 01:00 to 04:00 spans the skipped hour: two real hours.
        let overnight = schedule(days: WorkSchedule.allDays, hours: (1, 4))
        XCTAssertEqual(overnight.activeSeconds(from: ny(2026, 3, 8), to: ny(2026, 3, 9), calendar: newYork), 2 * hour)
    }

    func testSpringForwardWeek() {
        // Sat Mar 7 to Sat Mar 14: one 23h day.
        let start = ny(2026, 3, 7), end = ny(2026, 3, 14)
        XCTAssertEqual(end.timeIntervalSince(start), 7 * day - hour)
        XCTAssertEqual(schedule().activeSeconds(from: start, to: end, calendar: newYork), 5 * day)
        XCTAssertEqual(schedule(hours: (9, 18)).activeSeconds(from: start, to: end, calendar: newYork), 45 * hour)

        // Weekly pacing with a schedule stays exact across the jump.
        let r = PacingCalculator.calculate(
            utilization: 50, resetsAt: start.addingTimeInterval(WindowKind.weeklyDuration), kind: .weekly,
            schedule: schedule(hours: (9, 18)), now: ny(2026, 3, 11, 13, 30), calendar: newYork
        )
        // Mon + Tue full (18h) + Wed 9:00-13:30 (4.5h) = 22.5h of 45h.
        XCTAssertEqual(r.expectedUsage, 50, accuracy: 1e-9)
    }

    func testFallBackDayAndWeek() {
        // Sun Nov 1 2026: clocks fall back 02:00 -> 01:00.
        let all = schedule(days: WorkSchedule.allDays)
        XCTAssertEqual(all.activeSeconds(from: ny(2026, 11, 1), to: ny(2026, 11, 2), calendar: newYork), 25 * hour)
        let fullDay = schedule(days: WorkSchedule.allDays, hours: (0, 24))
        XCTAssertEqual(fullDay.activeSeconds(from: ny(2026, 11, 1), to: ny(2026, 11, 2), calendar: newYork), 25 * hour)

        let start = ny(2026, 10, 31), end = ny(2026, 11, 7)
        XCTAssertEqual(end.timeIntervalSince(start), 7 * day + hour)
        XCTAssertEqual(schedule().activeSeconds(from: start, to: end, calendar: newYork), 5 * day)
        XCTAssertEqual(schedule(days: WorkSchedule.allDays, hours: (9, 18)).activeSeconds(from: start, to: end, calendar: newYork), 63 * hour)
    }
}
