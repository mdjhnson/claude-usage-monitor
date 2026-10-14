import XCTest
@testable import PaceBarCore

final class AppVersionTests: XCTestCase {
    func testParsesWithAndWithoutPrefix() {
        XCTAssertEqual(AppVersion("1.0.3")?.components, [1, 0, 3])
        XCTAssertEqual(AppVersion("v1.0.3")?.components, [1, 0, 3])
        XCTAssertEqual(AppVersion(" V2 ")?.components, [2])
        XCTAssertEqual(AppVersion("v1.0.3")?.description, "1.0.3")
    }

    func testRejectsNonNumeric() {
        for bad in ["", "v", "1.0.3-beta", "1..2", "1.0.", ".1", "latest", "1.x", "١.٢"] {
            XCTAssertNil(AppVersion(bad), bad)
        }
    }

    func testMissingComponentsCountAsZero() throws {
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))
        XCTAssertFalse(try XCTUnwrap(AppVersion("1.0")) < XCTUnwrap(AppVersion("1.0.0")))
    }

    func testOrdersNumerically() throws {
        let v = { (s: String) in try XCTUnwrap(AppVersion(s)) }
        XCTAssertLessThan(try v("1.0.9"), try v("1.0.10"))
        XCTAssertLessThan(try v("1.0.2"), try v("v1.0.3"))
        XCTAssertLessThan(try v("1.9"), try v("2.0"))
        XCTAssertLessThan(try v("1.0"), try v("1.0.1"))
        XCTAssertGreaterThan(try v("1.1"), try v("1.0.99"))
    }

    func testUpdateCheckIsDue() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertTrue(UpdateCheck.isDue(lastChecked: nil, now: now))
        XCTAssertFalse(UpdateCheck.isDue(lastChecked: now.addingTimeInterval(-6 * day), now: now))
        XCTAssertTrue(UpdateCheck.isDue(lastChecked: now.addingTimeInterval(-7 * day), now: now))
        XCTAssertTrue(UpdateCheck.isDue(lastChecked: now.addingTimeInterval(day), now: now), "a future date means the clock moved")
    }
}

final class UpdateClientTests: XCTestCase {
    var client: UpdateClient!

    override func setUp() {
        StubProtocol.state.reset()
        let config = UsageClient.makeConfiguration()
        config.protocolClasses = [StubProtocol.self]
        client = UpdateClient(configuration: config)
    }

    private func respond(_ status: Int, headers: [String: String] = [:], body: String = "{}") {
        StubProtocol.state.reply = .response(status: status, headers: headers, body: Data(body.utf8))
    }

    private func fetchError() async -> UpdateClientError? {
        do {
            _ = try await client.latestVersion()
            return nil
        } catch {
            return error
        }
    }

    func test200DecodesTagAndSendsNoCredentials() async throws {
        respond(200, body: #"{"tag_name":"v1.2.3","html_url":"https://evil.example","assets":[]}"#)
        let version = try await client.latestVersion()
        XCTAssertEqual(version.components, [1, 2, 3])

        let sent = try XCTUnwrap(StubProtocol.state.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://api.github.com/repos/mdjhnson/claude-usage-monitor/releases/latest")
        XCTAssertEqual(sent.httpMethod, "GET")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "User-Agent"), "PaceBar")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertNil(sent.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(sent.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(sent.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func test404IsNoReleases() async {
        respond(404, body: #"{"message":"Not Found"}"#)
        let error = await fetchError()
        XCTAssertEqual(error, .noReleases)
    }

    func testRateLimitIs429OrExhausted403() async {
        respond(403, headers: ["X-RateLimit-Remaining": "0"])
        let exhausted = await fetchError()
        XCTAssertEqual(exhausted, .rateLimited)
        respond(429)
        let tooMany = await fetchError()
        XCTAssertEqual(tooMany, .rateLimited)
    }

    func testOther403IsNotRateLimited() async {
        respond(403, headers: ["X-RateLimit-Remaining": "42"])
        let forbidden = await fetchError()
        XCTAssertEqual(forbidden, .http(status: 403))
        respond(403)
        let bare = await fetchError()
        XCTAssertEqual(bare, .http(status: 403))
    }

    func testOtherStatus() async {
        respond(500)
        let error = await fetchError()
        XCTAssertEqual(error, .http(status: 500))
    }

    func testGarbageAndUnreadableTagsAreDecodingErrors() async {
        for body in ["<html>", #"{"name":"no tag"}"#, #"{"tag_name":"nightly"}"#, #"{"tag_name":"v1.0.3-beta"}"#] {
            respond(200, body: body)
            let error = await fetchError()
            XCTAssertEqual(error, .decoding, body)
        }
    }

    func testOversizedBodyIsDecodingError() async {
        let padding = String(repeating: " ", count: UpdateClient.maxBodyBytes)
        respond(200, body: #"{"tag_name":"v1.0.3"}"# + padding)
        let error = await fetchError()
        XCTAssertEqual(error, .decoding)
    }

    func testRedirectIsRefusedAndNeverFollowed() async {
        StubProtocol.state.reply = .redirect(status: 302, location: URL(string: "https://evil.example/latest")!)
        let error = await fetchError()
        XCTAssertEqual(error, .redirectRefused(status: 302))
        let hosts = StubProtocol.state.requests.compactMap { $0.url?.host }
        XCTAssertEqual(hosts, ["api.github.com"], "redirect target must never be requested")
    }

    func testWrongHostNeverSends() async {
        let bad = [
            "https://github.com/repos/mdjhnson/claude-usage-monitor/releases/latest",
            "http://api.github.com/repos/mdjhnson/claude-usage-monitor/releases/latest",
            "https://api.github.com.evil.example/releases/latest",
            "https://api.github.com:8443/releases/latest",
            "https://user:pass@api.github.com/releases/latest",
            "https://api.anthropic.com/api/oauth/usage",
        ]
        for string in bad {
            do {
                _ = try await client.fetch(URL(string: string)!)
                XCTFail("sent to \(string)")
            } catch {
                XCTAssertEqual(error, .hostNotAllowed, string)
            }
        }
        XCTAssertTrue(StubProtocol.state.requests.isEmpty, "nothing may be sent to a non-allowlisted URL")
    }

    func testHostLocksAreSeparate() {
        XCTAssertTrue(UpdateClient.isAllowed(URL(string: "https://API.GitHub.com:443/x")))
        XCTAssertFalse(UpdateClient.isAllowed(URL(string: "https://api.anthropic.com/api/oauth/usage")))
        XCTAssertFalse(UsageClient.isAllowed(URL(string: "https://api.github.com/x")))
        XCTAssertFalse(UpdateClient.isAllowed(nil))
    }

    func testNetworkFailure() async {
        StubProtocol.state.reply = .failure(.timedOut)
        let error = await fetchError()
        XCTAssertEqual(error, .network(code: URLError.Code.timedOut.rawValue))
    }
}
