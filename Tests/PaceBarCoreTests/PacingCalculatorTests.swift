import XCTest
@testable import PaceBarCore

final class PacingCalculatorTests: XCTestCase {
    // Session window half elapsed: expected usage is exactly 50.
    let now = ny(2026, 6, 10, 12)
    var halfwayReset: Date { now.addingTimeInterval(2.5 * hour) }

    private func session(_ utilization: Double, margin: Double = 10, schedule: WorkSchedule = .default) -> PacingResult {
        PacingCalculator.calculate(
            utilization: utilization, resetsAt: halfwayReset, kind: .session,
            margin: margin, schedule: schedule, now: now, calendar: newYork
        )
    }

    func testExpectedUsageAndDelta() {
        let r = session(62)
        XCTAssertEqual(r.expectedUsage, 50)
        XCTAssertEqual(r.delta, 12)
        XCTAssertEqual(r.markerFraction, 0.5)
        XCTAssertFalse(r.usesSchedule)
    }

    func testZoneBoundaries() {
        XCTAssertEqual(session(39.99).zone, .chill)
        XCTAssertEqual(session(40).zone, .onTrack)      // delta exactly -m
        XCTAssertEqual(session(60).zone, .onTrack)      // delta exactly m
        XCTAssertEqual(session(60.01).zone, .warning)
        XCTAssertEqual(session(70).zone, .warning)      // delta exactly 2m
        XCTAssertEqual(session(70.01).zone, .hot)
    }

    func testZoneFunctionDirectly() {
        XCTAssertEqual(PacingCalculator.zone(delta: -10, margin: 10), .onTrack)
        XCTAssertEqual(PacingCalculator.zone(delta: -10.0001, margin: 10), .chill)
        XCTAssertEqual(PacingCalculator.zone(delta: 10, margin: 10), .onTrack)
        XCTAssertEqual(PacingCalculator.zone(delta: 20, margin: 10), .warning)
        XCTAssertEqual(PacingCalculator.zone(delta: 20.0001, margin: 10), .hot)
    }

    func testCustomMargin() {
        XCTAssertEqual(session(57, margin: 5).zone, .warning)   // delta 7 > 5
        XCTAssertEqual(session(57, margin: 20).zone, .onTrack)  // delta 7 <= 20
        XCTAssertEqual(session(61, margin: 5).zone, .hot)       // delta 11 > 10
        // Out-of-range margins clamp to 5...20.
        XCTAssertEqual(session(70, margin: 50).zone, .onTrack)  // clamped to 20, delta 20
        XCTAssertEqual(session(75, margin: 50).zone, .warning)  // delta 25 > 20
        XCTAssertEqual(session(57, margin: 1).zone, .warning)   // margin 5
    }

    func testClampsBeforeWindow() {
        let reset = now.addingTimeInterval(6 * hour) // window starts in an hour
        let r = PacingCalculator.calculate(utilization: 0, resetsAt: reset, kind: .session, now: now, calendar: newYork)
        XCTAssertEqual(r.expectedUsage, 0)
        XCTAssertEqual(r.zone, .onTrack)
    }

    func testClampsAfterWindow() {
        let reset = now.addingTimeInterval(-hour)
        let r = PacingCalculator.calculate(utilization: 80, resetsAt: reset, kind: .session, now: now, calendar: newYork)
        XCTAssertEqual(r.expectedUsage, 100)
        XCTAssertEqual(r.delta, -20)
        XCTAssertEqual(r.zone, .chill)
        XCTAssertNil(r.coolingDate)
    }

    func testSessionIgnoresSchedule() {
        // Saturday, outside any workweek: the session must use plain calendar time.
        let saturday = ny(2026, 6, 13, 12)
        let reset = saturday.addingTimeInterval(2.5 * hour)
        let strict = schedule(days: WorkSchedule.workweek, hours: (9, 18))
        let a = PacingCalculator.calculate(utilization: 55, resetsAt: reset, kind: .session, schedule: strict, now: saturday, calendar: newYork)
        let b = PacingCalculator.calculate(utilization: 55, resetsAt: reset, kind: .session, now: saturday, calendar: newYork)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.expectedUsage, 50)
        XCTAssertFalse(a.usesSchedule)
        XCTAssertTrue(a.offTimeRanges.isEmpty)
    }

    func testWeeklyCalendarModeWhenScheduleDisabled() {
        // Window Sat Jun 6 00:00 to Sat Jun 13 00:00, now Tue Jun 9 12:00 = 3.5 days of 7.
        let r = PacingCalculator.calculate(
            utilization: 50, resetsAt: ny(2026, 6, 13), kind: .weekly, now: ny(2026, 6, 9, 12), calendar: newYork
        )
        XCTAssertEqual(r.expectedUsage, 50, accuracy: 1e-9)
        XCTAssertFalse(r.usesSchedule)
    }

    func testWeeklyModelUsesSchedule() {
        let r = PacingCalculator.calculate(
            utilization: 0, resetsAt: ny(2026, 6, 13), kind: .weeklyModel("Sonnet"),
            schedule: schedule(), now: ny(2026, 6, 8), calendar: newYork
        )
        XCTAssertTrue(r.usesSchedule)
        XCTAssertEqual(r.expectedUsage, 0, accuracy: 1e-9) // Sat and Sun were off
    }

    func testQuipsAreDeterministic() {
        XCTAssertEqual(PacingQuips.message(zone: .onTrack, kind: .session, delta: 0), "Locked in")
        XCTAssertEqual(PacingQuips.message(zone: .onTrack, kind: .session, delta: 4.9), "Session rhythm")
        XCTAssertEqual(PacingQuips.message(zone: .onTrack, kind: .session, delta: -5), "Right on the hour")
        XCTAssertEqual(PacingQuips.message(zone: .hot, kind: .weekly, delta: 33), "Week's burning")
        XCTAssertEqual(PacingQuips.message(zone: .chill, kind: .weeklyModel("Opus"), delta: -16), "Plenty of week")
        XCTAssertEqual(PacingQuips.message(zone: .hot, kind: .weekly, delta: .infinity), "Week's burning")
        XCTAssertEqual(session(62).message, session(62.4).message)
    }

    func testNonFiniteUtilizationDoesNotCrash() {
        let r = session(.nan)
        XCTAssertTrue(r.delta.isNaN)
        XCTAssertNil(r.coolingDate)
    }
}
