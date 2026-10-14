import XCTest
@testable import PaceBarCore

final class AlertTrackerTests: XCTestCase {
    let reset = Date(timeIntervalSince1970: 1_800_000_000)

    func session(_ utilization: Double, zone: PacingZone? = .onTrack, resetsAt: Date? = nil) -> AlertInput {
        AlertInput(kind: .session, utilization: utilization, resetsAt: resetsAt ?? reset, zone: zone)
    }

    func update(_ tracker: inout AlertTracker, _ windows: AlertInput...) -> [AlertEvent] {
        tracker.update(windows, warningAt: 60, criticalAt: 85)
    }

    func testFirstSightingIsSilent() {
        var t = AlertTracker()
        XCTAssertEqual(update(&t, session(90, zone: .hot)), [])
        // Already critical and already hot: nothing repeats on the next refresh.
        XCTAssertEqual(update(&t, session(92, zone: .hot)), [])
    }

    func testThresholdsAlertOncePerCycle() {
        var t = AlertTracker()
        _ = update(&t, session(10))
        XCTAssertEqual(update(&t, session(61)), [.threshold(session(61), .warning)])
        XCTAssertEqual(update(&t, session(70)), [])
        XCTAssertEqual(update(&t, session(86)), [.threshold(session(86), .critical)])
        XCTAssertEqual(update(&t, session(99)), [])
    }

    func testJumpStraightToCriticalIsOneAlert() {
        var t = AlertTracker()
        _ = update(&t, session(10))
        XCTAssertEqual(update(&t, session(90)), [.threshold(session(90), .critical)])
    }

    func testUsageEasingOffDoesNotRearm() {
        var t = AlertTracker()
        _ = update(&t, session(10))
        _ = update(&t, session(65))
        XCTAssertEqual(update(&t, session(55)), [])
        XCTAssertEqual(update(&t, session(65)), [])
    }

    func testNewCycleRearmsThresholds() {
        var t = AlertTracker()
        _ = update(&t, session(10))
        _ = update(&t, session(65))
        let next = reset.addingTimeInterval(5 * 3600)
        XCTAssertEqual(update(&t, session(5, resetsAt: next)), [])
        XCTAssertEqual(update(&t, session(62, resetsAt: next)), [.threshold(session(62, resetsAt: next), .warning)])
    }

    func testResetJitterIsNotANewCycle() {
        var t = AlertTracker()
        _ = update(&t, session(10))
        _ = update(&t, session(65))
        XCTAssertEqual(update(&t, session(66, resetsAt: reset.addingTimeInterval(1.5))), [])
    }

    func testSessionGapStartsANewCycle() {
        var t = AlertTracker()
        _ = update(&t, session(10))
        _ = update(&t, session(65))
        // The session ends (no reset time), then a new one starts already past the threshold.
        XCTAssertEqual(update(&t, AlertInput(kind: .session, utilization: 0, resetsAt: nil, zone: nil)), [])
        let next = reset.addingTimeInterval(5 * 3600)
        XCTAssertEqual(update(&t, session(61, resetsAt: next)), [.threshold(session(61, resetsAt: next), .warning)])
    }

    func testHotThenBackOnPace() {
        var t = AlertTracker()
        _ = update(&t, session(30, zone: .onTrack))
        XCTAssertEqual(update(&t, session(40, zone: .warning)), [])
        XCTAssertEqual(update(&t, session(50, zone: .hot)), [.runningHot(session(50, zone: .hot))])
        XCTAssertEqual(update(&t, session(50, zone: .hot)), [])
        // Watch out is between Hot and On track: no flapping.
        XCTAssertEqual(update(&t, session(50, zone: .warning)), [])
        XCTAssertEqual(update(&t, session(50, zone: .hot)), [])
        XCTAssertEqual(update(&t, session(50, zone: .onTrack)), [.backOnPace(session(50, zone: .onTrack))])
        XCTAssertEqual(update(&t, session(50, zone: .hot)), [.runningHot(session(50, zone: .hot))])
    }

    func testNewCycleClearsHotWithoutBackOnPace() {
        var t = AlertTracker()
        _ = update(&t, session(30))
        _ = update(&t, session(50, zone: .hot))
        let next = reset.addingTimeInterval(5 * 3600)
        XCTAssertEqual(update(&t, session(1, zone: .chill, resetsAt: next)), [])
    }

    func testWindowsAreIndependentAndForgottenWhenDropped() {
        var t = AlertTracker()
        let weekly = AlertInput(kind: .weekly, utilization: 10, resetsAt: reset, zone: .onTrack)
        _ = update(&t, session(10), weekly)
        XCTAssertEqual(update(&t, session(61), weekly), [.threshold(session(61), .warning)])
        // Weekly disappears, then returns already past the threshold: silent baseline again.
        _ = update(&t, session(61))
        let back = AlertInput(kind: .weekly, utilization: 70, resetsAt: reset, zone: .onTrack)
        XCTAssertEqual(update(&t, session(61), back), [])
    }

    func testReminderPlanning() {
        let now = reset.addingTimeInterval(-3600)
        let weekly = AlertInput(kind: .weekly, utilization: 10, resetsAt: reset.addingTimeInterval(3 * 86_400), zone: .onTrack)
        let noReset = AlertInput(kind: .weeklyModel("Fable"), utilization: 10, resetsAt: nil, zone: nil)
        let plan = ResetReminderPlanner.plan([session(10), weekly, noReset], lead: { kind in
            switch kind {
            case .session: 15 * 60
            case .weekly: 2 * 3600
            case .weeklyModel: 3600
            }
        }, now: now)
        XCTAssertEqual(plan, [
            ResetReminder(kind: .session, resetsAt: reset, fireAt: reset.addingTimeInterval(-15 * 60), lead: 15 * 60),
            ResetReminder(kind: .weekly, resetsAt: weekly.resetsAt!, fireAt: weekly.resetsAt!.addingTimeInterval(-2 * 3600), lead: 2 * 3600),
        ])
    }

    func testReminderSkippedWhenTooLateOrOff() {
        let now = reset.addingTimeInterval(-10 * 60)
        XCTAssertEqual(ResetReminderPlanner.plan([session(10)], lead: { _ in 15 * 60 }, now: now), [])
        XCTAssertEqual(ResetReminderPlanner.plan([session(10)], lead: { _ in nil }, now: now), [])
        XCTAssertEqual(ResetReminderPlanner.plan([session(10)], lead: { _ in 0 }, now: now), [])
    }
}
