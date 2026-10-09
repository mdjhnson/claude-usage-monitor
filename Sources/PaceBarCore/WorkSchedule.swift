import Foundation

/// Optional workweek pacing: only active days and hours advance the expected pace.
public struct WorkSchedule: Equatable, Sendable {
    /// Gregorian weekday numbers, 1 = Sunday ... 7 = Saturday.
    public static let allDays: Set<Int> = Set(1...7)
    public static let workweek: Set<Int> = [2, 3, 4, 5, 6]

    public var enabled: Bool
    public var activeDays: Set<Int>
    public var hoursEnabled: Bool
    /// 0...23, local time.
    public var startHour: Int
    /// 1...24, local time. 24 means midnight at the end of the day.
    public var endHour: Int

    public static let `default` = WorkSchedule(
        enabled: false, activeDays: workweek, hoursEnabled: false, startHour: 9, endHour: 18
    )

    public init(enabled: Bool, activeDays: Set<Int>, hoursEnabled: Bool, startHour: Int, endHour: Int) {
        self.enabled = enabled
        self.activeDays = activeDays
        self.hoursEnabled = hoursEnabled
        self.startHour = startHour
        self.endHour = endHour
    }

    /// Valid selected days, or all seven when the selection is empty.
    public var effectiveDays: Set<Int> {
        let valid = activeDays.filter { (1...7).contains($0) }
        return valid.isEmpty ? Self.allDays : valid
    }

    /// The daily hour window, or nil when hours are off or the window is empty.
    public var effectiveHours: (start: Int, end: Int)? {
        guard hoursEnabled else { return nil }
        let start = min(max(startHour, 0), 23)
        let end = min(max(endHour, 1), 24)
        return end > start ? (start, end) : nil
    }

    /// True when the schedule actually removes time from the week. Otherwise pacing is
    /// identical to calendar mode and the cheaper calendar math is used.
    public var isRestricting: Bool {
        enabled && (effectiveDays.count < 7 || effectiveHours != nil)
    }

    /// Active intervals between two instants, built by walking calendar days.
    ///
    /// Day boundaries come from `startOfDay` plus one day and hour bounds from
    /// `date(bySettingHour:)`, so 23 and 25 hour DST days stay correct.
    public func activeIntervals(from start: Date, to end: Date, calendar: Calendar) -> [DateInterval] {
        guard start < end else { return [] }
        let days = effectiveDays
        let hours = effectiveHours
        var result: [DateInterval] = []
        var cursor = start
        var guardCount = 0

        while cursor < end, guardCount < 400 {
            guardCount += 1
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dayStart),
                  nextMidnight > cursor else { break }
            let segmentEnd = min(nextMidnight, end)

            if days.contains(calendar.component(.weekday, from: cursor)) {
                var lo = cursor
                var hi = segmentEnd
                if let hours {
                    let hourStart = calendar.date(bySettingHour: hours.start, minute: 0, second: 0, of: dayStart) ?? dayStart
                    let hourEnd = hours.end >= 24
                        ? nextMidnight
                        : (calendar.date(bySettingHour: hours.end, minute: 0, second: 0, of: dayStart) ?? nextMidnight)
                    lo = max(lo, hourStart)
                    hi = min(hi, hourEnd)
                }
                if hi > lo { result.append(DateInterval(start: lo, end: hi)) }
            }
            cursor = segmentEnd
        }
        return result
    }

    public func activeSeconds(from start: Date, to end: Date, calendar: Calendar) -> TimeInterval {
        activeIntervals(from: start, to: end, calendar: calendar).reduce(0) { $0 + $1.duration }
    }
}
