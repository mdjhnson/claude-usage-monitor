import XCTest
@testable import PaceBarCore

final class CredentialParserTests: XCTestCase {
    private func parse(_ json: String) -> OAuthCredential? {
        CredentialParser.parse(Data(json.utf8))
    }

    func testValidPayloadMilliseconds() {
        let c = parse(#"{"claudeAiOauth":{"accessToken":"tok-abc","refreshToken":"r","expiresAt":1783494000000,"scopes":["user:inference"]}}"#)
        XCTAssertEqual(c?.accessToken, "tok-abc")
        XCTAssertEqual(c?.expiresAt, Date(timeIntervalSince1970: 1_783_494_000))
    }

    func testExpiresAtInSeconds() {
        let c = parse(#"{"claudeAiOauth":{"accessToken":"tok","expiresAt":1783494000}}"#)
        XCTAssertEqual(c?.expiresAt, Date(timeIntervalSince1970: 1_783_494_000))
    }

    func testExpiresAtAsStringOrMissing() {
        XCTAssertEqual(parse(#"{"claudeAiOauth":{"accessToken":"t","expiresAt":"1783494000000"}}"#)?.expiresAt,
                       Date(timeIntervalSince1970: 1_783_494_000))
        XCTAssertNil(parse(#"{"claudeAiOauth":{"accessToken":"t"}}"#)?.expiresAt)
        XCTAssertNil(parse(#"{"claudeAiOauth":{"accessToken":"t","expiresAt":-5}}"#)?.expiresAt)
        XCTAssertNotNil(parse(#"{"claudeAiOauth":{"accessToken":"t","expiresAt":null}}"#))
    }

    func testMissingOAuthBlock() {
        // A shadowing item may carry only MCP OAuth data.
        XCTAssertNil(parse(#"{"mcpOAuth":{"server":{"accessToken":"x"}}}"#))
        XCTAssertNil(parse(#"{"claudeAiOauth":"not an object"}"#))
    }

    func testEmptyOrMissingToken() {
        XCTAssertNil(parse(#"{"claudeAiOauth":{"accessToken":"","expiresAt":1}}"#))
        XCTAssertNil(parse(#"{"claudeAiOauth":{"accessToken":"   ","expiresAt":1}}"#))
        XCTAssertNil(parse(#"{"claudeAiOauth":{"expiresAt":1783494000000}}"#))
        XCTAssertNil(parse(#"{"claudeAiOauth":{"accessToken":42}}"#))
    }

    func testMalformedPayload() {
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("not json"))
        XCTAssertNil(parse("[]"))
    }

    func testTrailingNewlineFromSecurityTool() {
        XCTAssertEqual(CredentialParser.parse(Data("{\"claudeAiOauth\":{\"accessToken\":\"t\"}}\n".utf8))?.accessToken, "t")
    }

    func testChoosesLatestOfSeveral() {
        let a = OAuthCredential(accessToken: "a", expiresAt: Date(timeIntervalSince1970: 100))
        let b = OAuthCredential(accessToken: "b", expiresAt: Date(timeIntervalSince1970: 300))
        let c = OAuthCredential(accessToken: "c", expiresAt: Date(timeIntervalSince1970: 200))
        let d = OAuthCredential(accessToken: "d", expiresAt: nil)
        XCTAssertEqual(CredentialParser.best(of: [a, b, c, d])?.accessToken, "b")
        XCTAssertEqual(CredentialParser.best(of: [d])?.accessToken, "d")
        XCTAssertNil(CredentialParser.best(of: []))
    }

    func testExpiry() {
        let c = OAuthCredential(accessToken: "t", expiresAt: Date(timeIntervalSince1970: 100))
        XCTAssertTrue(c.isExpired(now: Date(timeIntervalSince1970: 100)))
        XCTAssertFalse(c.isExpired(now: Date(timeIntervalSince1970: 99)))
        XCTAssertFalse(OAuthCredential(accessToken: "t", expiresAt: nil).isExpired(now: .distantFuture))
    }

    func testDescriptionNeverRevealsToken() {
        let c = OAuthCredential(accessToken: "sk-ant-oat01-SECRET", expiresAt: nil)
        XCTAssertFalse(String(describing: c).contains("SECRET"))
        XCTAssertFalse(String(reflecting: c).contains("SECRET"))
        XCTAssertFalse("\(c)".contains("SECRET"))
        var dumped = ""
        dump(c, to: &dumped)
        XCTAssertFalse(dumped.contains("SECRET"))
    }
}
