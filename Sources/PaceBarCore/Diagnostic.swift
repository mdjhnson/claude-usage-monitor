import Foundation

/// Describes the shape of a JSON response without its values.
///
/// Output is one line per key path with the JSON types seen there, for example
/// `$.limits[].scope.model.display_name: string = "Sonnet"`. Values are shown only at three
/// exact paths that name limit types and models, never people. Date-like strings report only
/// their format. Keys that aren't plain lowercase field names print as `<key>`.
public enum ResponseShape {
    static let valuePaths: Set<String> = [
        "$.limits[].kind",
        "$.limits[].group",
        "$.limits[].scope.model.display_name",
    ]
    static let hexLike = CharacterSet(charactersIn: "0123456789abcdefABCDEF-_")

    public static func describe(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return "(not JSON, \(data.count) bytes)"
        }
        var types: [String: Set<String>] = [:]
        walk(object, path: "$", into: &types)
        return types.keys.sorted().map { "\($0): \(types[$0]!.sorted().joined(separator: " | "))" }
            .joined(separator: "\n")
    }

    private static func walk(_ value: Any, path: String, into types: inout [String: Set<String>]) {
        switch value {
        case let dict as [String: Any]:
            types[path, default: []].insert("object")
            for (k, v) in dict {
                walk(v, path: path + "." + safeKey(k), into: &types)
            }
        case let array as [Any]:
            types[path, default: []].insert("array(\(array.count))")
            for element in array { walk(element, path: path + "[]", into: &types) }
        case let s as String:
            types[path, default: []].insert(describeString(s, path: path))
        case let n as NSNumber:
            types[path, default: []].insert(CFGetTypeID(n) == CFBooleanGetTypeID() ? "bool" : "number")
        case is NSNull:
            types[path, default: []].insert("null")
        default:
            types[path, default: []].insert("unknown")
        }
    }

    /// Plain field names (`five_hour`, `amber_cistern`) print as-is; anything else could be a
    /// name, email or id used as a key, so it is replaced.
    static func safeKey(_ key: String) -> String {
        let plain = !key.isEmpty && key.count <= 40
            && key.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
        return plain && !isIdentifierLike(key) ? key : "<key>"
    }

    private static func describeString(_ s: String, path: String) -> String {
        if valuePaths.contains(path), s.count <= 40, !isIdentifierLike(s) {
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
        let hex = s.unicodeScalars.filter { hexLike.contains($0) }
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
