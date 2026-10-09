import XCTest
@testable import PaceBarCore

/// Mirrors the response shape from a real "Copy diagnostic" on 2026-10-09 (migrated account,
/// macOS 27). Key names and types are real; every value is invented.
final class RealShapeFixtureTests: XCTestCase {
    static let fixture = """
    {
      "amber_cistern": null, "amber_gauge": null, "amber_ladder": null, "brass_thimble": null,
      "cedar_ember": null, "cinder_cove": null, "copper_kite": null, "harbor_lantern": null,
      "iguana_necktie": null, "juniper_tide": null, "nimbus_quill": null, "omelette_promotional": null,
      "tangelo": null, "wattle_ember": null,
      "extra_usage": {
        "credits_ever_enabled": false, "currency": null, "daily": null, "decimal_places": null,
        "disabled_reason": null, "is_enabled": false, "monthly_limit": null, "spend_limit_reached": false,
        "used_credits": null, "user_disabled": false, "utilization": null, "weekly": null
      },
      "five_hour": {
        "limit_dollars": null, "locked_reason": null, "remaining_dollars": null,
        "resets_at": "2026-10-09T21:00:00.412873+00:00", "used_dollars": null, "utilization": 3.0
      },
      "seven_day": {
        "limit_dollars": null, "locked_reason": null, "remaining_dollars": null,
        "resets_at": "2026-10-16T07:59:59.412873+00:00", "used_dollars": null, "utilization": 12.0
      },
      "seven_day_breakdown": null, "seven_day_cowork": null, "seven_day_oauth_apps": null,
      "seven_day_omelette": null, "seven_day_opus": null, "seven_day_sonnet": null,
      "limits": [
        { "group": "session", "is_active": true, "kind": "session", "percent": 3.0,
          "resets_at": "2026-10-09T21:00:00.412873+00:00", "scope": null, "severity": "normal" },
        { "group": "weekly", "is_active": false, "kind": "weekly_all", "percent": 12.0,
          "resets_at": "2026-10-16T07:59:59.412873+00:00", "scope": null, "severity": "normal" },
        { "group": "weekly", "is_active": false, "kind": "weekly_scoped", "percent": 0.0,
          "resets_at": "2026-10-16T08:00:00+00:00",
          "scope": { "model": { "display_name": "Fable", "id": null }, "surface": null }, "severity": "normal" }
      ],
      "member_dashboard_available": false,
      "spend": {
        "auto_reload": null, "balance": null, "can_purchase_credits": false, "can_toggle": false, "cap": null,
        "disabled_reason": null, "disclaimer": "Invented text.", "enabled": false, "limit": null,
        "percent": 0, "severity": "normal",
        "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 }
      },
      "weekly_scoped_shares": [
        { "allowance_percent_of_weekly": 100, "limit_index": 2, "used_percent_of_weekly": 0 }
      ]
    }
    """

    func testDecodesRealShape() throws {
        let r = try JSONDecoder().decode(UsageResponse.self, from: Data(Self.fixture.utf8))
        XCTAssertEqual(r.windows.map(\.kind), [.session, .weekly, .weeklyModel("Fable")])
        XCTAssertEqual(r.windows.map(\.bucket.utilization), [3, 12, 0])
        XCTAssertEqual(r.fiveHour?.resetsAt, ISO8601.parse("2026-10-09T21:00:00.412873+00:00"))
        XCTAssertEqual(r.windows[2].bucket.resetsAt, ISO8601.parse("2026-10-16T08:00:00Z"))
    }

    func testDiagnosticShapeMatchesRealKeys() {
        let shape = ResponseShape.describe(Data(Self.fixture.utf8))
        for line in [
            "$.five_hour.resets_at: string<iso8601+fraction>",
            "$.limits[].kind: string = \"session\" | string = \"weekly_all\" | string = \"weekly_scoped\"",
            "$.limits[].resets_at: string<iso8601+fraction> | string<iso8601>",
            "$.limits[].scope.model.display_name: string = \"Fable\"",
            "$.weekly_scoped_shares: array(1)",
        ] {
            XCTAssertTrue(shape.contains(line), line)
        }
        XCTAssertFalse(shape.contains("Invented"))
        XCTAssertFalse(shape.contains("USD"))
    }
}
