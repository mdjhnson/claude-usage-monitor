import XCTest
@testable import PaceBarCore

final class WidgetSnapshotTests: XCTestCase {
    let reset = Date(timeIntervalSince1970: 1_800_000_000)

    func display(schedule: WorkSchedule = .default, theme: [String: UInt32] = ["hot": 0xFF453A]) -> WidgetSnapshot.Display {
        WidgetSnapshot.Display(
            margin: 10, schedule: schedule, colorMode: "pacing", warningAt: 60, criticalAt: 85,
            usageGraph: true, weeklyDayMarkers: "linesAndNames", theme: theme
        )
    }

    func snapshot(fetchedAt: Date? = nil, hasError: Bool = false, refresh: TimeInterval = 180) -> WidgetSnapshot {
        let t0 = reset.addingTimeInterval(-3 * hour)
        return WidgetSnapshot(
            fetchedAt: fetchedAt ?? reset.addingTimeInterval(-hour),
            refreshInterval: refresh,
            hasError: hasError,
            windows: [
                .init(kind: .session, utilization: 42, resetsAt: reset,
                      samples: [UsageSample(date: t0, utilization: 10), UsageSample(date: t0.addingTimeInterval(180), utilization: 12)]),
                .init(kind: .weekly, utilization: 18, resetsAt: reset.addingTimeInterval(3 * day), samples: []),
                .init(kind: .weeklyModel("Sonnet"), utilization: 7, resetsAt: nil, samples: []),
            ],
            display: display(schedule: schedule(hours: (9, 18)), theme: ["hot": 0xFF453A, "background": 0x141417])
        )
    }

    func store() -> WidgetSnapshotStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return WidgetSnapshotStore(fileURL: dir.appendingPathComponent(WidgetSnapshotStore.fileName))
    }

    func testRoundTripsThroughTheFile() throws {
        let s = store()
        XCTAssertNil(s.read())
        let original = snapshot()
        try s.write(original)
        XCTAssertEqual(s.read(), original)
    }

    func testModelKindsKeepTheirName() throws {
        let s = store()
        try s.write(snapshot())
        XCTAssertEqual(s.read()?.windows.map(\.kind), [.session, .weekly, .weeklyModel("Sonnet")])
    }

    func testUnreadableFileReadsAsNil() throws {
        let s = store()
        try Data("{\"not\": \"a snapshot\"}".utf8).write(to: s.fileURL)
        XCTAssertNil(s.read())
    }

    /// The file holds usage and display settings only.
    func testEncodedKeysAreTheExpectedOnes() throws {
        let s = store()
        try s.write(snapshot())
        let text = try String(contentsOf: s.fileURL, encoding: .utf8)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["fetchedAt", "refreshInterval", "hasError", "windows", "display"])
        for word in ["token", "access", "refresh_token", "bearer", "oauth", "secret", "credential"] {
            XCTAssertFalse(text.lowercased().contains(word), "snapshot mentions \(word)")
        }
    }

    func testPacingMatchesTheCalculator() {
        let snap = snapshot()
        let now = reset.addingTimeInterval(-2 * hour)
        for window in snap.windows {
            let expected = window.resetsAt.map {
                PacingCalculator.calculate(
                    utilization: window.utilization, resetsAt: $0, kind: window.kind,
                    margin: 10, schedule: snap.display.schedule, now: now, calendar: newYork
                )
            }
            XCTAssertEqual(snap.pacing(for: window, now: now, calendar: newYork), expected)
        }
        XCTAssertNil(snap.paceCurve(for: snap.windows[2], calendar: newYork))
    }

    func testStaleness() {
        let fetched = reset.addingTimeInterval(-hour)
        XCTAssertFalse(snapshot(fetchedAt: fetched).isStale(now: fetched.addingTimeInterval(5 * 60)))
        // Never under 10 minutes, even at a 3 minute refresh.
        XCTAssertFalse(snapshot(fetchedAt: fetched).isStale(now: fetched.addingTimeInterval(9 * 60)))
        XCTAssertTrue(snapshot(fetchedAt: fetched).isStale(now: fetched.addingTimeInterval(11 * 60)))
        XCTAssertFalse(snapshot(fetchedAt: fetched, refresh: 600).isStale(now: fetched.addingTimeInterval(19 * 60)))
        XCTAssertTrue(snapshot(fetchedAt: fetched, hasError: true).isStale(now: fetched))
    }

    // MARK: Downsampling

    func samples(_ count: Int) -> [UsageSample] {
        (0..<count).map { UsageSample(date: reset.addingTimeInterval(Double($0) * 60), utilization: Double($0)) }
    }

    func testDownsampleLeavesShortSeriesAlone() {
        XCTAssertEqual(UsageSample.downsampled(samples(50), to: 120), samples(50))
        XCTAssertEqual(UsageSample.downsampled([], to: 120), [])
    }

    func testDownsampleBoundsKeepsEndsAndOrder() {
        let all = samples(2_000)
        let thinned = UsageSample.downsampled(all, to: 120)
        XCTAssertLessThanOrEqual(thinned.count, 120)
        XCTAssertGreaterThan(thinned.count, 100)
        XCTAssertEqual(thinned.first, all.first)
        XCTAssertEqual(thinned.last, all.last)
        XCTAssertEqual(thinned.map(\.date), thinned.map(\.date).sorted())
        XCTAssertEqual(Set(thinned.map(\.date)).count, thinned.count)
    }

    func testDownsampleTinyLimits() {
        let all = samples(10)
        XCTAssertEqual(UsageSample.downsampled(all, to: 2), [all[0], all[9]])
        XCTAssertEqual(UsageSample.downsampled(all, to: 1), [all[9]])
        XCTAssertEqual(UsageSample.downsampled(all, to: 0), [])
    }
}
