import XCTest
@testable import PaceBarCore

/// Records every request the session tries to load and answers from a canned handler.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Reply {
        case response(status: Int, headers: [String: String], body: Data)
        case redirect(status: Int, location: URL)
        case failure(URLError.Code)
    }

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _reply: Reply = .response(status: 200, headers: [:], body: Data("{}".utf8))
        private var _requests: [URLRequest] = []

        var reply: Reply {
            get { lock.withLock { _reply } }
            set { lock.withLock { _reply = newValue } }
        }
        var requests: [URLRequest] { lock.withLock { _requests } }
        func record(_ r: URLRequest) { lock.withLock { _requests.append(r) } }
        func reset() { lock.withLock { _requests = []; _reply = .response(status: 200, headers: [:], body: Data("{}".utf8)) } }
    }

    static let state = State()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.state.record(request)
        let url = request.url!
        switch Self.state.reply {
        case .response(let status, let headers, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let status, let location):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": location.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: location), redirectResponse: response)
            // If the redirect is refused, the 3xx itself is the final response.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

final class UsageClientTests: XCTestCase {
    let credential = OAuthCredential(accessToken: "test-token", expiresAt: nil)
    var client: UsageClient!

    override func setUp() {
        StubProtocol.state.reset()
        let config = UsageClient.makeConfiguration()
        config.protocolClasses = [StubProtocol.self]
        client = UsageClient(configuration: config)
    }

    private func respond(_ status: Int, headers: [String: String] = [:], body: String = "{}") {
        StubProtocol.state.reply = .response(status: status, headers: headers, body: Data(body.utf8))
    }

    private func fetchError() async -> UsageClientError? {
        do {
            _ = try await client.fetchUsage(credential: credential, now: Date(timeIntervalSince1970: 1_783_494_000))
            return nil
        } catch {
            return error
        }
    }

    func test200DecodesAndSendsExpectedHeaders() async throws {
        respond(200, body: #"{"five_hour":{"utilization":42,"resets_at":"2026-07-08T07:00:00Z"},"secret":"zzz"}"#)
        let result = try await client.fetchUsage(credential: credential)
        XCTAssertEqual(result.usage.fiveHour?.utilization, 42)
        XCTAssertFalse(result.shape.contains("zzz"))

        let sent = try XCTUnwrap(StubProtocol.state.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(sent.httpMethod, "GET")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "User-Agent"), "claude-code/0.0.0")
        XCTAssertNil(sent.value(forHTTPHeaderField: "Cookie"))
    }

    func test200WithGarbageIsDecodingError() async {
        respond(200, body: "<html>maintenance</html>")
        let error = await fetchError()
        XCTAssertEqual(error, .decoding)
    }

    func test401And403AreTokenExpired() async {
        respond(401)
        let unauthorized = await fetchError()
        XCTAssertEqual(unauthorized, .tokenExpired(status: 401))
        respond(403)
        let forbidden = await fetchError()
        XCTAssertEqual(forbidden, .tokenExpired(status: 403))
    }

    func test429WithNumericRetryAfter() async {
        respond(429, headers: ["Retry-After": "120"])
        let error = await fetchError()
        XCTAssertEqual(error, .rateLimited(retryAfter: 120))
    }

    func test429WithDateRetryAfter() async {
        respond(429, headers: ["Retry-After": "Wed, 08 Jul 2026 07:05:00 GMT"])
        let error = await fetchError()
        XCTAssertEqual(error, .rateLimited(retryAfter: 300))
    }

    func test429WithoutRetryAfter() async {
        respond(429)
        let error = await fetchError()
        XCTAssertEqual(error, .rateLimited(retryAfter: nil))
    }

    func testOtherStatus() async {
        respond(503)
        let error = await fetchError()
        XCTAssertEqual(error, .http(status: 503))
    }

    func testRedirectIsRefusedAndNeverFollowed() async {
        StubProtocol.state.reply = .redirect(status: 302, location: URL(string: "https://evil.example/steal")!)
        let error = await fetchError()
        XCTAssertEqual(error, .redirectRefused(status: 302))
        let hosts = StubProtocol.state.requests.compactMap { $0.url?.host }
        XCTAssertEqual(hosts, ["api.anthropic.com"], "redirect target must never be requested")
    }

    func testSameHostRedirectIsAlsoRefused() async {
        StubProtocol.state.reply = .redirect(status: 307, location: URL(string: "https://api.anthropic.com/elsewhere")!)
        let error = await fetchError()
        XCTAssertEqual(error, .redirectRefused(status: 307))
        XCTAssertEqual(StubProtocol.state.requests.count, 1)
    }

    func testWrongHostNeverSends() async {
        let bad = [
            "https://evil.example/api/oauth/usage",
            "http://api.anthropic.com/api/oauth/usage",
            "https://api.anthropic.com.evil.example/api/oauth/usage",
            "https://api.anthropic.com:8443/api/oauth/usage",
            "https://user:pass@api.anthropic.com/api/oauth/usage",
            "https://anthropic.com/api/oauth/usage",
        ]
        for string in bad {
            do {
                _ = try await client.fetch(URL(string: string)!, credential: credential, now: Date())
                XCTFail("sent to \(string)")
            } catch {
                XCTAssertEqual(error, .hostNotAllowed, string)
            }
        }
        XCTAssertTrue(StubProtocol.state.requests.isEmpty, "nothing may be sent to a non-allowlisted URL")
    }

    func testHostLock() {
        XCTAssertTrue(UsageClient.isAllowed(URL(string: "https://api.anthropic.com/api/oauth/usage")))
        XCTAssertTrue(UsageClient.isAllowed(URL(string: "https://API.Anthropic.com:443/x")))
        XCTAssertFalse(UsageClient.isAllowed(nil))
    }

    func testNetworkFailure() async {
        StubProtocol.state.reply = .failure(.notConnectedToInternet)
        let error = await fetchError()
        XCTAssertEqual(error, .network(code: URLError.Code.notConnectedToInternet.rawValue))
    }

    func testConfigurationStoresNothing() {
        let c = UsageClient.makeConfiguration()
        XCTAssertNil(c.urlCache)
        XCTAssertNil(c.httpCookieStorage)
        XCTAssertNil(c.urlCredentialStorage)
        XCTAssertFalse(c.httpShouldSetCookies)
    }
}

final class KeychainTokenReaderTests: XCTestCase {
    /// Exercises the real subprocess path against a service that cannot exist. No credentials involved.
    func testMissingItemMapsToNotFound() {
        let service = "PaceBar-test-nonexistent-\(UUID().uuidString)"
        XCTAssertEqual(KeychainTokenReader.runSecurity(service: service, account: nil, timeout: 10).failureValue, .notFound)
        XCTAssertEqual(KeychainTokenReader.readSync(service: service, timeout: 10).failureValue, .notFound)
        XCTAssertEqual(KeychainTokenReader(service: service).itemCount(), 0)
    }

    func testMinimalEnvironmentOnlyHasHome() {
        let env = KeychainTokenReader.minimalEnvironment()
        XCTAssertEqual(Array(env.keys), ["HOME"])
        XCTAssertEqual(env["HOME"], NSHomeDirectory())
    }

    func testMostRelevantErrorOrdering() {
        XCTAssertEqual(KeychainTokenReader.mostRelevant([.notFound, .accessDenied, .timedOut]), .accessDenied)
        XCTAssertEqual(KeychainTokenReader.mostRelevant([.notFound, .unusablePayload]), .unusablePayload)
        XCTAssertEqual(KeychainTokenReader.mostRelevant([.notFound, .unexpectedExit(1)]), .unexpectedExit(1))
        XCTAssertEqual(KeychainTokenReader.mostRelevant([]), .notFound)
    }
}

extension Result {
    var failureValue: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
