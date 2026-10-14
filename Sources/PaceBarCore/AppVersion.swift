import Foundation

/// A release version such as "1.0.3", from `CFBundleShortVersionString` or a GitHub tag ("v1.0.3").
/// Only dot-separated numbers parse; a pre-release suffix such as "-beta" does not.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        guard !numbers.isEmpty else { return nil }
        components = numbers
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    /// Missing components count as zero, so 1.0 equals 1.0.0.
    private func padded(to count: Int) -> [Int] {
        components + Array(repeating: 0, count: max(0, count - components.count))
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.components.count, b.components.count)
        return a.padded(to: n) == b.padded(to: n)
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.components.count, b.components.count)
        return a.padded(to: n).lexicographicallyPrecedes(b.padded(to: n))
    }
}

/// When the optional automatic update check runs.
public enum UpdateCheck {
    public static let interval: TimeInterval = 7 * 24 * 3600

    /// Due when never checked, a week has passed, or the last check is in the future (clock change).
    public static func isDue(lastChecked: Date?, now: Date) -> Bool {
        guard let lastChecked else { return true }
        let elapsed = now.timeIntervalSince(lastChecked)
        return elapsed < 0 || elapsed >= interval
    }
}
