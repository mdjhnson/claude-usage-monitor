import Foundation

/// A Claude Code OAuth access token. Never printed: every description is redacted.
public struct OAuthCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let accessToken: String
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    public func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    public var description: String { "OAuthCredential(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Parses the JSON payload Claude Code stores in the Keychain.
public enum CredentialParser {
    /// Epoch values at or above this are milliseconds; below are seconds.
    /// 1e11 seconds is the year 5138, 1e11 ms is 1973, so the split is unambiguous.
    static let millisecondThreshold: Double = 1e11

    /// Returns nil for payloads without `claudeAiOauth` or with an empty token.
    public static func parse(_ data: Data) -> OAuthCredential? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return OAuthCredential(accessToken: trimmed, expiresAt: expiry(from: oauth["expiresAt"]))
    }

    static func expiry(from value: Any?) -> Date? {
        let raw: Double?
        switch value {
        case let n as NSNumber: raw = n.doubleValue
        case let s as String: raw = Double(s.trimmingCharacters(in: .whitespaces))
        default: raw = nil
        }
        guard let raw, raw.isFinite, raw > 0 else { return nil }
        let seconds = raw >= millisecondThreshold ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }

    /// Picks the credential with the latest `expiresAt`. A missing expiry sorts first.
    public static func best(of credentials: [OAuthCredential]) -> OAuthCredential? {
        credentials.max { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }
    }
}
