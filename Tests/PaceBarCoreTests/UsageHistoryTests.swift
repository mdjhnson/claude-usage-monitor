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

    private func value(_ curve: [GraphPoint], at x: Double) -> Double {
        GraphMath.value(of: curve, at: x) ?? .nan
    }

    func testNearestIndex() {
        let points = [GraphPoint(x: 0.1, y: 1), GraphPoint(x: 0.4, y: 2), GraphPoint(x: 0.5, y: 3)]
        XCTAssertEqual(GraphMath.nearestIndex(in: points, toX: 0), 0)
        XCTAssertEqual(GraphMath.nearestIndex(in: points, toX: 0.3), 1)
        XCTAssertEqual(GraphMath.nearestIndex(in: points, toX: 0.45), 1) // tie: earlier
        XCTAssertEqual(GraphMath.nearestIndex(in: points, toX: 0.46), 2)
        XCTAssertEqual(GraphMath.nearestIndex(in: points, toX: 1), 2)
        XCTAssertNil(GraphMath.nearestIndex(in: [], toX: 0.5))
    }

    func testInterpolation() {
        let curve = [GraphPoint(x: 0, y: 0), GraphPoint(x: 0.5, y: 50), GraphPoint(x: 0.5, y: 60), GraphPoint(x: 1, y: 100)]
        XCTAssertEqual(GraphMath.value(of: curve, at: 0.25), 25)
        XCTAssertEqual(GraphMath.value(of: curve, at: 0.75), 80)
        XCTAssertEqual(GraphMath.value(of: curve, at: -1), 0)
        XCTAssertEqual(GraphMath.value(of: curve, at: 2), 100)
        XCTAssertNil(GraphMath.value(of: [], at: 0.5))
    }
}

final class GraphDayTests: XCTestCase {
    func testWeekStartingAt4AMHasTwoPartialEnds() {
        // Fri 4 AM to the next Fri 4 AM, New York, no DST change.
        let start = ny(2026, 10, 9, 4), end = ny(2026, 10, 16, 4)
        let days = GraphMath.days(from: start, to: end, calendar: newYork)
        XCTAssertEqual(days.count, 8)
        XCTAssertEqual(days.first?.start, 0)
        XCTAssertEqual(days.last?.end, 1)
        XCTAssertEqual(days[0].end, 20.0 / 168, accuracy: 1e-9) // Fri 4 AM → Sat midnight
        XCTAssertEqual(days[1].date, ny(2026, 10, 10))
        XCTAssertEqual(days[7].end - days[7].start, 4.0 / 168, accuracy: 1e-9) // Fri midnight → 4 AM
        // Contiguous.
        for (a, b) in zip(days, days.dropFirst()) { XCTAssertEqual(a.end, b.start) }
    }

    func testWindowOnMidnightsHasSevenWholeDays() {
        let days = GraphMath.days(from: ny(2026, 10, 12), to: ny(2026, 10, 19), calendar: newYork)
        XCTAssertEqual(days.count, 7)
        for day in days { XCTAssertEqual(day.end - day.start, 1.0 / 7, accuracy: 1e-9) }
    }

    func testDSTDayHasItsRealLength() {
        // US DST ends Sun Nov 1, 2026: that day is 25 hours long.
        let start = ny(2026, 10, 29), end = ny(2026, 11, 5)
        let days = GraphMath.days(from: start, to: end, calendar: newYork)
        XCTAssertEqual(days.count, 7)
        let span = end.timeIntervalSince(start) / 3600 // 169 hours
        XCTAssertEqual(span, 169)
        let sunday = days.first { $0.date == ny(2026, 11, 1) }
        XCTAssertEqual((sunday!.end - sunday!.start) * span, 25, accuracy: 1e-9)
    }

    func testEmptyWindow() {
        let t = ny(2026, 10, 12)
        XCTAssertEqual(GraphMath.days(from: t, to: t, calendar: newYork), [])
        XCTAssertEqual(GraphMath.days(from: t, to: t.addingTimeInterval(-1), calendar: newYork), [])
    }
}
