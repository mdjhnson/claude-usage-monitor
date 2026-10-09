import Foundation

/// Describes the shape of a JSON response without its values.
///
/// Output is one line per key path with the JSON types seen there, for example
/// `limits[].scope.model.display_name: string = "Sonnet"`. Only a small allowlist of
/// enum-like keys (`kind`, `group`, `display_name`) shows its value, because those name
/// limit types and models, not people. Date-like strings report only their format.
/// Keys that look like identifiers (UUIDs, long hex, emails) are replaced.
public enum ResponseShape {
    static let valueAllowlist: Set<String> = ["kind", "group", "display_name"]

    public static func describe(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return "(not JSON, \(data.count) bytes)"
        }
        var types: [String: Set<String>] = [:]
        walk(object, path: "$", key: nil, into: &types)
        return types.keys.sorted().map { "\($0): \(types[$0]!.sorted().joined(separator: " | "))" }
            .joined(separator: "\n")
    }

    private static func walk(_ value: Any, path: String, key: String?, into types: inout [String: Set<String>]) {
        switch value {
        case let dict as [String: Any]:
            types[path, default: []].insert("object")
            for (k, v) in dict {
                let safeKey = isIdentifierLike(k) ? "<id>" : k
                walk(v, path: path + "." + safeKey, key: k, into: &types)
            }
        case let array as [Any]:
            types[path, default: []].insert("array(\(array.count))")
            for element in array { walk(element, path: path + "[]", key: key, into: &types) }
        case let s as String:
            types[path, default: []].insert(describeString(s, key: key))
        case let n as NSNumber:
            types[path, default: []].insert(CFGetTypeID(n) == CFBooleanGetTypeID() ? "bool" : "number")
        case is NSNull:
            types[path, default: []].insert("null")
        default:
            types[path, default: []].insert("unknown")
        }
    }

    private static func describeString(_ s: String, key: String?) -> String {
        if let key, valueAllowlist.contains(key), s.count <= 40, !isIdentifierLike(s) {
            let printable = s.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 0x20 && $0 != "\"" }
            if printable { return "string = \"\(s)\"" }
        }
        if s.contains("T"), ISO8601.parse(s) != nil {
            return s.contains(".") ? "string<iso8601+fraction>" : "string<iso8601>"
        }
        return "string"
    }

    static func isIdentifierLike(_ s: String) -> Bool {
        if s.contains("@") { return true }
        if UUID(uuidString: s) != nil { return true }
        let hex = s.unicodeScalars.filter { CharacterSet(charactersIn: "0123456789abcdefABCDEF-_").contains($0) }
        if s.count >= 16 && hex.count == s.unicodeScalars.count { return true }
        // Long runs with digits mixed in (account ids, tokens) are never printed.
        let digits = s.filter(\.isNumber).count
        return s.count >= 20 && digits >= 4
    }
}

/// Assembles the "Copy diagnostic" report from an explicit allowlist of facts.
public struct DiagnosticReport: Sendable {
    public var appVersion: String
    public var osVersion: String
    public var keychainItemCount: Int?
    public var tokenPresent: Bool
    public var tokenExpiresIn: TimeInterval?
    public var lastHTTPStatus: Int?
    public var lastErrorKind: String?
    public var refreshInterval: TimeInterval
    public var backoffActive: Bool
    public var responseShape: String?

    public init(appVersion: String, osVersion: String, keychainItemCount: Int?, tokenPresent: Bool,
                tokenExpiresIn: TimeInterval?, lastHTTPStatus: Int?, lastErrorKind: String?,
                refreshInterval: TimeInterval, backoffActive: Bool, responseShape: String?) {
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.keychainItemCount = keychainItemCount
        self.tokenPresent = tokenPresent
        self.tokenExpiresIn = tokenExpiresIn
        self.lastHTTPStatus = lastHTTPStatus
        self.lastErrorKind = lastErrorKind
        self.refreshInterval = refreshInterval
        self.backoffActive = backoffActive
        self.responseShape = responseShape
    }

    public var text: String {
        var lines = [
            "PaceBar diagnostic (redacted: no token, no identifiers, no values)",
            "app: \(appVersion)",
            "macOS: \(osVersion)",
            "keychain items: \(keychainItemCount.map(String.init) ?? "unknown")",
            "token present: \(tokenPresent ? "yes" : "no")",
            "token expiry: \(tokenExpiresIn.map(Self.relative) ?? "unknown")",
            "last HTTP status: \(lastHTTPStatus.map(String.init) ?? "none")",
            "last error: \(lastErrorKind ?? "none")",
            "refresh interval: \(Int(refreshInterval))s",
            "rate-limit backoff active: \(backoffActive ? "yes" : "no")",
            "",
            "response shape:",
        ]
        lines.append(responseShape ?? "(no successful response yet)")
        return lines.joined(separator: "\n")
    }

    static func relative(_ interval: TimeInterval) -> String {
        let minutes = Int((abs(interval) / 60).rounded())
        return interval >= 0 ? "in \(minutes) min" : "expired \(minutes) min ago"
    }
}
