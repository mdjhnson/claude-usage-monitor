import XCTest
@testable import PaceBarCore

final class UsageDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> UsageResponse {
        try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
    }

    func testFlatShape() throws {
        let r = try decode("""
        {
          "five_hour": { "utilization": 42, "resets_at": "2026-07-08T07:00:00Z" },
          "seven_day": { "utilization": 65.5, "resets_at": "2026-07-10T00:00:00.123Z" },
          "seven_day_sonnet": { "utilization": 30, "resets_at": "2026-07-10T00:00:00Z" },
          "seven_day_opus": null,
          "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null,
                           "utilization": null, "currency": null, "disabled_reason": "org_level_disabled" }
        }
        """)
        XCTAssertEqual(r.fiveHour, UsageBucket(utilization: 42, resetsAt: ISO8601.parse("2026-07-08T07:00:00Z")))
        XCTAssertEqual(r.sevenDay?.utilization, 65.5)
        XCTAssertEqual(r.windows.map(\.kind), [.session, .weekly, .weeklyModel("Sonnet")])
        XCTAssertEqual(r.windows.map(\.id), ["session", "weekly", "weekly.sonnet"])
    }

    /// The live shape on migrated accounts, as captured in TokenEater's test suite.
    func testMigratedLimitsShape() throws {
        let r = try decode("""
        {
          "five_hour": { "utilization": 19, "resets_at": null },
          "seven_day": { "utilization": 15, "resets_at": null },
          "seven_day_fable": null,
          "limits": [
            { "kind": "session", "group": "session", "percent": 19, "resets_at": null, "scope": null, "is_active": false },
            { "kind": "weekly_all", "group": "weekly", "percent": 15, "resets_at": null, "scope": null, "is_active": false },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 23,
              "resets_at": "2026-07-08T07:00:00.052047+00:00",
              "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
              "is_active": true }
          ]
        }
        """)
        XCTAssertEqual(r.fiveHour, UsageBucket(utilization: 19, resetsAt: nil))
        XCTAssertEqual(r.sevenDay, UsageBucket(utilization: 15, resetsAt: nil))
        XCTAssertEqual(r.windows.map(\.kind), [.session, .weekly, .weeklyModel("Fable")])
        let fable = r.windows[2].bucket
        XCTAssertEqual(fable.utilization, 23)
        XCTAssertEqual(fable.resetsAt!.timeIntervalSince1970, ISO8601.parse("2026-07-08T07:00:00Z")!.timeIntervalSince1970 + 0.052047, accuracy: 1e-6)
    }

    func testLimitsFillMissingFlatBuckets() throws {
        let r = try decode("""
        {
          "limits": [
            { "kind": "session", "percent": 12, "resets_at": "2026-07-08T07:00:00Z" },
            { "kind": "weekly_all", "percent": 34, "resets_at": "2026-07-10T07:00:00Z" },
            { "kind": "weekly_scoped", "percent": 56, "resets_at": "2026-07-10T07:00:00Z",
              "scope": { "model": { "display_name": "Sonnet" } } }
          ]
        }
        """)
        XCTAssertEqual(r.fiveHour?.utilization, 12)
        XCTAssertEqual(r.sevenDay?.utilization, 34)
        XCTAssertEqual(r.windows.last?.kind, .weeklyModel("Sonnet"))
    }

    func testFlatWinsWhenItHasResetTime() throws {
        let r = try decode("""
        {
          "seven_day_sonnet": { "utilization": 30, "resets_at": "2026-07-10T00:00:00Z" },
          "limits": [
            { "kind": "weekly_scoped", "percent": 99, "resets_at": "2026-07-10T00:00:00Z",
              "scope": { "model": { "display_name": "sonnet" } } }
          ]
        }
        """)
        XCTAssertEqual(r.windows.count, 1)
        XCTAssertEqual(r.windows[0].bucket.utilization, 30)
    }

    func testLimitsWinWhenFlatHasNoResetTime() throws {
        let r = try decode("""
        {
          "seven_day_opus": { "utilization": 5, "resets_at": null },
          "limits": [
            { "kind": "weekly_scoped", "percent": 7, "resets_at": "2026-07-10T00:00:00Z",
              "scope": { "model": { "display_name": "Opus" } } }
          ]
        }
        """)
        XCTAssertEqual(r.windows.count, 1)
        XCTAssertEqual(r.windows[0].bucket.utilization, 7)
    }

    func testBrokenBucketBecomesNil() throws {
        let r = try decode("""
        {
          "five_hour": "oops",
          "seven_day": { "utilization": "lots", "resets_at": "2026-07-10T00:00:00Z" },
          "seven_day_sonnet": { "resets_at": "2026-07-10T00:00:00Z" },
          "seven_day_opus": { "utilization": 10, "resets_at": "2026-07-10T00:00:00Z" }
        }
        """)
        XCTAssertNil(r.fiveHour)
        XCTAssertNil(r.sevenDay)
        XCTAssertEqual(r.windows.map(\.kind), [.weeklyModel("Opus")])
    }

    func testBadLimitsElementIsSkippedIndividually() throws {
        let r = try decode("""
        {
          "limits": [
            42,
            { "kind": "weekly_scoped", "percent": "NaN?", "scope": { "model": { "display_name": "Sonnet" } } },
            { "kind": "weekly_scoped", "percent": 8, "resets_at": "2026-07-10T00:00:00Z",
              "scope": { "model": { "display_name": "Fable" } } }
          ]
        }
        """)
        XCTAssertEqual(r.windows.map(\.kind), [.weeklyModel("Fable")])
    }

    func testLimitsNotAnArrayIsIgnored() throws {
        let r = try decode(#"{ "five_hour": { "utilization": 1, "resets_at": null }, "limits": { "nope": true } }"#)
        XCTAssertEqual(r.windows.count, 1)
    }

    func testUnknownKeysIgnored() throws {
        let r = try decode("""
        {
          "five_hour": { "utilization": 3, "resets_at": "2026-07-08T07:00:00Z", "brand_new": [1, 2] },
          "seven_day_oauth_apps": { "utilization": 1, "resets_at": null },
          "something_else": { "deep": { "deeper": true } }
        }
        """)
        XCTAssertEqual(r.fiveHour?.utilization, 3)
        XCTAssertEqual(r.windows.count, 1)
    }

    func testEmptyObject() throws {
        XCTAssertTrue(try decode("{}").windows.isEmpty)
    }

    func testNonObjectTopLevelThrows() {
        XCTAssertThrowsError(try decode("[1,2,3]"))
        XCTAssertThrowsError(try decode("not json"))
    }

    func testUnparseableResetIsNil() throws {
        let r = try decode(#"{ "five_hour": { "utilization": 9, "resets_at": "next tuesday" } }"#)
        XCTAssertEqual(r.fiveHour, UsageBucket(utilization: 9, resetsAt: nil))
    }

    // MARK: ISO 8601

    func testISO8601Variants() {
        let base = ISO8601.parse("2026-07-08T07:00:00Z")!
        XCTAssertEqual(base.timeIntervalSince1970, 1_783_494_000)
        XCTAssertEqual(ISO8601.parse("2026-07-08T07:00:00+00:00"), base)
        XCTAssertEqual(ISO8601.parse("2026-07-08T09:00:00+02:00"), base)
        XCTAssertEqual(ISO8601.parse("2026-07-08T07:00:00.5Z")!.timeIntervalSince(base), 0.5, accuracy: 1e-5)
        XCTAssertEqual(ISO8601.parse("2026-07-08T07:00:00.123Z")!.timeIntervalSince(base), 0.123, accuracy: 1e-5)
        XCTAssertEqual(ISO8601.parse("2026-07-08T07:00:00.052047+00:00")!.timeIntervalSince(base), 0.052047, accuracy: 1e-5)
        XCTAssertNil(ISO8601.parse("2026-07-08"))
        XCTAssertNil(ISO8601.parse("2026-07-08T07:00:00.Z"))
        XCTAssertNil(ISO8601.parse(""))
    }
}
