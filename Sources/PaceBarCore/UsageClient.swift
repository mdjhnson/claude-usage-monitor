import Foundation
import os

public enum UsageClientError: Error, Equatable, Sendable {
    /// 401 or 403: Claude Code needs to refresh its login.
    case tokenExpired(status: Int)
    /// 429, with the parsed `Retry-After` in seconds when present.
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other non-2xx status.
    case http(status: Int)
    /// A 3xx the session refused to follow.
    case redirectRefused(status: Int)
    /// The request or response URL was not https://api.anthropic.com.
    case hostNotAllowed
    /// Transport failure (`URLError.Code` raw value).
    case network(code: Int)
    /// 200 with a body that is not a usage object.
    case decoding
}

public struct UsageFetchResult: Sendable {
    public let usage: UsageResponse
    /// Redacted key/type dump of the raw body, for "Copy diagnostic".
    public let shape: String
}

/// The app's only network client. One host, no redirects, no cookies, no cache.
public final class UsageClient: Sendable {
    public static let allowedHost = "api.anthropic.com"
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let userAgent = "claude-code/0.0.0"
    static let betaHeader = "oauth-2025-04-20"
    static let maxBodyBytes = 1 << 20

    private let session: URLSession
    private static let log = Logger(subsystem: "io.github.mdjhnson.pacebar", category: "network")

    /// - Parameter configuration: tests pass `makeConfiguration()` with a stub protocol added.
    public init(configuration: URLSessionConfiguration = UsageClient.makeConfiguration()) {
        session = URLSession(configuration: configuration, delegate: RedirectRefuser(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public static func makeConfiguration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.waitsForConnectivity = false
        c.httpMaximumConnectionsPerHost = 1
        c.tlsMinimumSupportedProtocolVersion = .TLSv12
        return c
    }

    public func fetchUsage(credential: OAuthCredential, now: Date = Date()) async throws(UsageClientError) -> UsageFetchResult {
        try await fetch(Self.usageURL, credential: credential, now: now)
    }

    /// Exact host lock: https, host `api.anthropic.com`, default port, no user info.
    static func isAllowed(_ url: URL?) -> Bool {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.host?.lowercased() == allowedHost
            && (components.port == nil || components.port == 443)
            && components.user == nil && components.password == nil
    }

    func fetch(_ url: URL, credential: OAuthCredential, now: Date) async throws(UsageClientError) -> UsageFetchResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + credential.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Asserted on the built request, immediately before sending.
        guard Self.isAllowed(request.url) else {
            Self.log.fault("refused to send to a non-allowlisted URL")
            throw .hostNotAllowed
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            Self.log.error("request failed: \(error.code.rawValue, privacy: .public)")
            throw .network(code: error.code.rawValue)
        } catch {
            throw .network(code: URLError.Code.unknown.rawValue)
        }

        guard let http = response as? HTTPURLResponse, Self.isAllowed(http.url) else { throw .hostNotAllowed }
        Self.log.info("usage status \(http.statusCode, privacy: .public)")

        switch http.statusCode {
        case 200:
            guard data.count <= Self.maxBodyBytes,
                  let usage = try? JSONDecoder().decode(UsageResponse.self, from: data) else { throw .decoding }
            return UsageFetchResult(usage: usage, shape: ResponseShape.describe(data))
        case 401, 403:
            throw .tokenExpired(status: http.statusCode)
        case 429:
            throw .rateLimited(retryAfter: RetryAfter.parse(http.value(forHTTPHeaderField: "Retry-After"), now: now))
        case 300...399:
            throw .redirectRefused(status: http.statusCode)
        default:
            throw .http(status: http.statusCode)
        }
    }
}

/// Refuses every redirect. The 3xx response is delivered as-is and mapped to an error.
private final class RedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
