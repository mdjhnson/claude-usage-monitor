import Foundation
import os

public enum UpdateClientError: Error, Equatable, Sendable {
    /// 404: the repository has no published release yet.
    case noReleases
    /// 403 or 429: GitHub's unauthenticated rate limit (60 requests an hour per IP).
    case rateLimited
    /// Any other non-2xx status.
    case http(status: Int)
    /// A 3xx the session refused to follow.
    case redirectRefused(status: Int)
    /// The request or response URL was not https://api.github.com.
    case hostNotAllowed
    /// Transport failure (`URLError.Code` raw value).
    case network(code: Int)
    /// 200 with a body that has no readable version tag.
    case decoding
}

/// Reads the latest release's version tag from GitHub. It sends no credentials or account data,
/// downloads nothing else, and is locked down like `UsageClient`: one fixed URL, no redirects,
/// no cookies, no cache.
public final class UpdateClient: Sendable {
    public static let allowedHost = "api.github.com"
    static let latestURL = URL(string: "https://api.github.com/repos/mdjhnson/claude-usage-monitor/releases/latest")!
    /// GitHub rejects requests without a User-Agent.
    static let userAgent = "PaceBar"
    static let maxBodyBytes = 1 << 20

    private let session: URLSession
    private static let log = Logger(subsystem: "io.github.mdjhnson.pacebar", category: "update")

    /// - Parameter configuration: tests pass `UsageClient.makeConfiguration()` with a stub protocol added.
    public init(configuration: URLSessionConfiguration = UsageClient.makeConfiguration()) {
        session = URLSession(configuration: configuration, delegate: RedirectRefuser(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func latestVersion() async throws(UpdateClientError) -> AppVersion {
        try await fetch(Self.latestURL)
    }

    static func isAllowed(_ url: URL?) -> Bool {
        UsageClient.isAllowed(url, host: allowedHost)
    }

    private struct Release: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }

    func fetch(_ url: URL) async throws(UpdateClientError) -> AppVersion {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

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
        Self.log.info("latest release status \(http.statusCode, privacy: .public)")

        switch http.statusCode {
        case 200:
            guard data.count <= Self.maxBodyBytes,
                  let release = try? JSONDecoder().decode(Release.self, from: data),
                  let version = AppVersion(release.tagName) else { throw .decoding }
            return version
        case 404:
            throw .noReleases
        case 403, 429:
            throw .rateLimited
        case 300...399:
            throw .redirectRefused(status: http.statusCode)
        default:
            throw .http(status: http.statusCode)
        }
    }
}
