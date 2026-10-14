import XCTest
@testable import PaceBarCore

final class UsageHistoryTests: XCTestCase {
    let reset = Date(timeIntervalSince1970: 1_800_000_000)

    func window(_ utilization: Double, resetsAt: Date?, kind: WindowKind = .session) -> UsageWindow {
        UsageWindow(kind: kind, bucket: UsageBucket(utilization: utilization, resetsAt: resetsAt))
    }

    func testRecordsInOrderAndSkipsOutOfOrder() {
        var h = UsageHistory()
        let t0 = reset.addingTimeInterval(-3 * hour)
        h.record([window(10, resetsAt: reset)], at: t0)
        h.record([window(20, resetsAt: reset)], at: t0.addingTimeInterval(180))
        h.record([window(99, resetsAt: reset)], at: t0.addingTimeInterval(60)) // older than the last
        XCTAssertEqual(h.samples(for: .session).map(\.utilization), [10, 20])
    }

    func testNewCycleClearsOnlyThatWindow() {
        var h = UsageHistory()
        let t0 = reset.addingTimeInterval(-hour)
        let weeklyReset = reset.addingTimeInterval(3 * day)
        h.record([window(40, resetsAt: reset), window(30, resetsAt: weeklyReset, kind: .weekly)], at: t0)
        let next = reset.addingTimeInterval(5 * hour)
        h.record([window(2, resetsAt: next), window(31, resetsAt: weeklyReset, kind: .weekly)], at: reset.addingTimeInterval(60))
        XCTAssertEqual(h.samples(for: .session).map(\.utilization), [2])
        XCTAssertEqual(h.samples(for: .weekly).map(\.utilization), [30, 31])
    }

    func testJitterKeepsTheCycle() {
        var h = UsageHistory()
        h.record([window(10, resetsAt: reset)], at: reset.addingTimeInterval(-hour))
        h.record([window(12, resetsAt: reset.addingTimeInterval(0.8))], at: reset.addingTimeInterval(-hour + 180))
        XCTAssertEqual(h.samples(for: .session).count, 2)
    }

    func testThinsPastTheCap() {
        var h = UsageHistory()
        let t0 = reset.addingTimeInterval(-6 * day)
        for i in 0...UsageHistory.maxSamples {
            h.record([window(Double(i) / 100, resetsAt: reset, kind: .weekly)], at: t0.addingTimeInterval(Double(i) * 60))
        }
        let samples = h.samples(for: .weekly)
        XCTAssertLessThanOrEqual(samples.count, UsageHistory.maxSamples)
        XCTAssertEqual(samples.first?.utilization, 0)
        XCTAssertEqual(samples.last?.utilization, Double(UsageHistory.maxSamples) / 100)
    }

    func testResetCycle() {
        XCTAssertFalse(ResetCycle.isNew(old: reset, new: reset.addingTimeInterval(120)))
        XCTAssertTrue(ResetCycle.isNew(old: reset, new: reset.addingTimeInterval(5 * hour)))
        XCTAssertTrue(ResetCycle.isNew(old: reset, new: nil))
        XCTAssertTrue(ResetCycle.isNew(old: nil, new: reset))
        XCTAssertFalse(ResetCycle.isNew(old: nil, new: nil))
    }

    func testPaceCurveIsDiagonalWithoutSchedule() {
        let curve = PacingCalculator.paceCurve(resetsAt: reset, kind: .weekly, schedule: .default, calendar: newYork)
        XCTAssertEqual(curve, [GraphPoint(x: 0, y: 0), GraphPoint(x: 1, y: 100)])
        let session = PacingCalculator.paceCurve(resetsAt: reset, kind: .session, schedule: schedule(), calendar: newYork)
        XCTAssertEqual(session, [GraphPoint(x: 0, y: 0), GraphPoint(x: 1, y: 100)])
    }

    func testPaceCurveFollowsWorkweek() {
        // Weekly window from Wed 00:00 to the next Wed 00:00, Mon–Fri active: 5 active days.
        let resetsAt = ny(2026, 10, 21)
        let curve = PacingCalculator.paceCurve(resetsAt: resetsAt, kind: .weekly, schedule: schedule(), calendar: newYork)
        XCTAssertEqual(curve.first, GraphPoint(x: 0, y: 0))
        XCTAssertEqual(curve.last, GraphPoint(x: 1, y: 100))
        // Monotonic in both axes.
        for (a, b) in zip(curve, curve.dropFirst()) {
            XCTAssertLessThanOrEqual(a.x, b.x)
            XCTAssertLessThanOrEqual(a.y, b.y)
        }
        // Saturday noon is 3.5 days in; Wed, Thu, Fri are done, so expected is 3/5 = 60%.
        let saturday = ny(2026, 10, 17, 12).timeIntervalSince(resetsAt.addingTimeInterval(-WindowKind.weeklyDuration)) / WindowKind.weeklyDuration
        XCTAssertEqual(value(curve, at: saturday), 60, accuracy: 0.01)
        // Matches the calculator's expected usage at an arbitrary active moment.
        let monday = ny(2026, 10, 19, 15)
        let expected = PacingCalculator.calculate(utilization: 0, resetsAt: resetsAt, kind: .weekly, schedule: schedule(), now: monday, calendar: newYork).expectedUsage
        let mondayX = monday.timeIntervalSince(resetsAt.addingTimeInterval(-WindowKind.weeklyDuration)) / WindowKind.weeklyDuration
        XCTAssertEqual(value(curve, at: mondayX), expected, accuracy: 0.01)
    }

    /// Linear interpolation along the polyline.
    private func value(_ curve: [GraphPoint], at x: Double) -> Double {
        for (a, b) in zip(curve, curve.dropFirst()) where a.x <= x && x <= b.x {
            return b.x == a.x ? b.y : a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
        }
        return curve.last?.y ?? 0
    }
}
