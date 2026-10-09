import XCTest
@testable import PaceBarCore

final class BackoffTests: XCTestCase {
    func testExponentialGrowthAndCap() {
        var p = BackoffPolicy()
        XCTAssertEqual(p.recordRateLimit(retryAfter: nil, baseInterval: 180), 180)
        XCTAssertEqual(p.recordRateLimit(retryAfter: nil, baseInterval: 180), 360)
        XCTAssertEqual(p.recordRateLimit(retryAfter: nil, baseInterval: 180), 720)
        XCTAssertEqual(p.recordRateLimit(retryAfter: nil, baseInterval: 180), 900) // capped
        for _ in 0..<40 { _ = p.recordRateLimit(retryAfter: nil, baseInterval: 180) }
        XCTAssertEqual(p.recordRateLimit(retryAfter: nil, baseInterval: 180), 900)
    }

    func testRetryAfterTakesPrecedence() {
        var p = BackoffPolicy()
        XCTAssertEqual(p.recordRateLimit(retryAfter: 42, baseInterval: 180), 42)
        // Honored beyond the exponential cap...
        XCTAssertEqual(p.recordRateLimit(retryAfter: 1800, baseInterval: 180), 1800)
        // ...up to the one hour sanity bound.
        XCTAssertEqual(p.recordRateLimit(retryAfter: 86_400, baseInterval: 180), 3600)
        XCTAssertEqual(p.consecutiveRateLimits, 3)
    }

    func testResetOnSuccess() {
        var p = BackoffPolicy()
        _ = p.recordRateLimit(retryAfter: nil, baseInterval: 60)
        _ = p.recordRateLimit(retryAfter: nil, baseInterval: 60)
        p.recordSuccess()
        XCTAssertEqual(p.consecutiveRateLimits, 0)
        XCTAssertEqual(p.recordRateLimit(retryAfter: nil, baseInterval: 60), 60)
    }

    func testRetryAfterParsing() {
        let now = Date(timeIntervalSince1970: 1_783_494_000) // Wed, 08 Jul 2026 07:00:00 GMT
        XCTAssertEqual(RetryAfter.parse("120", now: now), 120)
        XCTAssertEqual(RetryAfter.parse(" 30 ", now: now), 30)
        XCTAssertEqual(RetryAfter.parse("Wed, 08 Jul 2026 07:05:00 GMT", now: now), 300)
        XCTAssertNil(RetryAfter.parse("Wed, 08 Jul 2026 06:00:00 GMT", now: now)) // past
        XCTAssertNil(RetryAfter.parse("0", now: now))
        XCTAssertNil(RetryAfter.parse("-5", now: now))
        XCTAssertNil(RetryAfter.parse("soon", now: now))
        XCTAssertNil(RetryAfter.parse("", now: now))
        XCTAssertNil(RetryAfter.parse(nil, now: now))
    }
}

final class DiagnosticTests: XCTestCase {
    func testShapeHasKeysAndTypesButNoValues() {
        let json = """
        {
          "five_hour": { "utilization": 42.5, "resets_at": "2026-07-08T07:00:00.052047+00:00" },
          "seven_day": { "utilization": 10, "resets_at": null },
          "extra_usage": { "is_enabled": false, "currency": "USD", "used_credits": 27000 },
          "limits": [
            { "kind": "weekly_scoped", "percent": 23, "scope": { "model": { "id": "claude-sonnet-x-20260101", "display_name": "Sonnet" } } }
          ],
          "account": { "email_address": "someone@example.com", "uuid": "123e4567-e89b-12d3-a456-426614174000" },
          "123e4567-e89b-12d3-a456-426614174000": { "secret_org_name": "Acme Private" }
        }
        """
        let shape = ResponseShape.describe(Data(json.utf8))

        XCTAssertTrue(shape.contains("$.five_hour.utilization: number"))
        XCTAssertTrue(shape.contains("$.five_hour.resets_at: string<iso8601+fraction>"))
        XCTAssertTrue(shape.contains("$.seven_day.resets_at: null"))
        XCTAssertTrue(shape.contains("$.extra_usage.is_enabled: bool"))
        XCTAssertTrue(shape.contains("$.limits: array(1)"))
        XCTAssertTrue(shape.contains("$.limits[].kind: string = \"weekly_scoped\""))
        XCTAssertTrue(shape.contains("$.limits[].scope.model.display_name: string = \"Sonnet\""))
        XCTAssertTrue(shape.contains("$.<key>.secret_org_name: string"))

        for secret in ["42.5", "27000", "USD", "someone", "example.com", "123e4567", "Acme", "claude-sonnet-x", "2026-07-08"] {
            XCTAssertFalse(shape.contains(secret), "leaked \(secret)")
        }
    }

    /// Values print only at the exact allowlisted paths, so a future `user.display_name` or an
    /// object keyed by a person's name can't reach the pasteboard.
    func testValuesOnlyAtAllowlistedPathsAndKeysSanitized() {
        let json = """
        {
          "user": { "display_name": "Jane Doe", "kind": "admin" },
          "organization": { "display_name": "Acme" },
          "members": { "Jane Doe": { "role": "owner" }, "jane@example.com": 1, "x\u{FF20}y": 2 },
          "limits": [ { "kind": "weekly_scoped", "scope": { "model": { "display_name": "Sonnet" } } } ]
        }
        """
        let shape = ResponseShape.describe(Data(json.utf8))
        XCTAssertTrue(shape.contains("$.limits[].scope.model.display_name: string = \"Sonnet\""))
        XCTAssertTrue(shape.contains("$.limits[].kind: string = \"weekly_scoped\""))
        XCTAssertTrue(shape.contains("$.user.display_name: string\n"))
        XCTAssertTrue(shape.contains("$.members.<key>.role: string"))
        for leak in ["Jane", "Doe", "Acme", "admin", "jane@", "example.com", "\u{FF20}", "owner"] {
            XCTAssertFalse(shape.contains(leak), "leaked \(leak)")
        }
    }

    func testSafeKey() {
        XCTAssertEqual(ResponseShape.safeKey("five_hour"), "five_hour")
        XCTAssertEqual(ResponseShape.safeKey("amber_cistern"), "amber_cistern")
        XCTAssertEqual(ResponseShape.safeKey("Jane Doe"), "<key>")
        XCTAssertEqual(ResponseShape.safeKey("deadbeefdeadbeefdeadbeef"), "<key>")
        XCTAssertEqual(ResponseShape.safeKey(""), "<key>")
        XCTAssertEqual(ResponseShape.safeKey(String(repeating: "a", count: 41)), "<key>")
    }

    func testNonJSON() {
        XCTAssertEqual(ResponseShape.describe(Data("<html>".utf8)), "(not JSON, 6 bytes)")
    }

    func testReportText() {
        let report = DiagnosticReport(
            appVersion: "1.0 (1)", osVersion: "27.0", keychainItemCount: 2, tokenPresent: true,
            tokenExpiresIn: -120, lastHTTPStatus: 429, lastErrorKind: "rateLimited",
            refreshInterval: 180, backoffActive: true, responseShape: nil
        ).text
        XCTAssertTrue(report.contains("keychain items: 2"))
        XCTAssertTrue(report.contains("token expiry: expired 2 min ago"))
        XCTAssertTrue(report.contains("last HTTP status: 429"))
        XCTAssertTrue(report.contains("(no successful response yet)"))
    }
}
