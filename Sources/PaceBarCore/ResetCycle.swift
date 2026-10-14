import Foundation

/// Tells a real reset apart from timestamp jitter. A window's cycle changes only when its reset
/// time moves, never because usage eased off as time caught up with it.
public enum ResetCycle {
    /// Reset times that differ by less than this are the same cycle (the API's timestamps jitter).
    public static let tolerance: TimeInterval = 5 * 60

    /// True when `new` belongs to a different cycle than `old`. A session that ends (reset time
    /// goes nil) or starts (nil to a date) is a new cycle too.
    public static func isNew(old: Date?, new: Date?) -> Bool {
        switch (old, new) {
        case (nil, nil): false
        case (nil, _?), (_?, nil): true
        case let (old?, new?): abs(new.timeIntervalSince(old)) > tolerance
        }
    }
}
