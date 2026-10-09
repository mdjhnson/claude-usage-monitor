import Foundation

/// Rate-limit backoff for HTTP 429.
///
/// A server `Retry-After` is honored as sent (up to a one hour sanity bound). Without it the
/// delay doubles from the poll interval per consecutive 429, capped at 15 minutes.
public struct BackoffPolicy: Equatable, Sendable {
    public static let cap: TimeInterval = 15 * 60
    public static let retryAfterBound: TimeInterval = 60 * 60

    public private(set) var consecutiveRateLimits = 0

    public init() {}

    /// Records a 429 and returns how long to wait before the next request.
    public mutating func recordRateLimit(retryAfter: TimeInterval?, baseInterval: TimeInterval) -> TimeInterval {
        consecutiveRateLimits += 1
        if let retryAfter, retryAfter > 0 {
            return min(retryAfter, Self.retryAfterBound)
        }
        let exponent = Double(min(consecutiveRateLimits - 1, 16))
        return min(max(baseInterval, 1) * pow(2, exponent), Self.cap)
    }

    public mutating func recordSuccess() {
        consecutiveRateLimits = 0
    }
}

/// Parses a `Retry-After` header: delta-seconds or an HTTP-date.
public enum RetryAfter {
    public static func parse(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Double(value), seconds.isFinite {
            return seconds > 0 ? seconds : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        let interval = date.timeIntervalSince(now)
        return interval > 0 ? interval : nil
    }
}
