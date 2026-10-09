import Foundation

/// Pure pacing math. No clocks, no globals: `now` and `calendar` are always parameters.
public enum PacingCalculator {
    public static let defaultMargin: Double = 10
    public static let marginRange: ClosedRange<Double> = 5...20

    public static func zone(delta: Double, margin: Double) -> PacingZone {
        if delta < -margin { return .chill }
        if delta <= margin { return .onTrack }
        if delta <= margin * 2 { return .warning }
        return .hot
    }

    public static func calculate(
        utilization: Double,
        resetsAt: Date,
        kind: WindowKind,
        margin: Double = defaultMargin,
        schedule: WorkSchedule = .default,
        now: Date,
        calendar: Calendar
    ) -> PacingResult {
        let margin = min(max(margin, marginRange.lowerBound), marginRange.upperBound)
        let duration = kind.duration
        let start = resetsAt.addingTimeInterval(-duration)
        let useSchedule = kind.usesSchedule && schedule.isRestricting

        let elapsedFraction: Double
        var offRanges: [ClosedRange<Double>] = []
        var isOffTime = false
        var activeIntervals: [DateInterval] = []
        var totalActive: TimeInterval = 0

        if useSchedule {
            activeIntervals = schedule.activeIntervals(from: start, to: resetsAt, calendar: calendar)
            totalActive = activeIntervals.reduce(0) { $0 + $1.duration }
            let clampedNow = min(max(now, start), resetsAt)
            let elapsedActive = activeIntervals.reduce(0.0) { sum, iv in
                sum + max(0, min(iv.end, clampedNow).timeIntervalSince(iv.start))
            }
            elapsedFraction = totalActive > 0 ? clamp01(elapsedActive / totalActive) : 0
            offRanges = gaps(between: activeIntervals, start: start, end: resetsAt, duration: duration)
            isOffTime = now >= start && now < resetsAt
                && !activeIntervals.contains { $0.start <= now && now < $0.end }
        } else {
            elapsedFraction = clamp01(now.timeIntervalSince(start) / duration)
        }

        let expected = elapsedFraction * 100
        let delta = utilization - expected
        let zone = zone(delta: delta, margin: margin)

        var cooling: Date?
        if delta > 0 {
            if useSchedule {
                cooling = scheduleCoolingDate(
                    needed: delta / 100 * totalActive, intervals: activeIntervals, now: now, resetsAt: resetsAt
                )
            } else {
                cooling = min(now.addingTimeInterval(delta / 100 * duration), resetsAt)
            }
        }

        let marker = useSchedule ? clamp01(now.timeIntervalSince(start) / duration) : elapsedFraction

        return PacingResult(
            actualUsage: utilization,
            expectedUsage: expected,
            delta: delta,
            zone: zone,
            coolingDate: cooling,
            message: PacingQuips.message(zone: zone, kind: kind, delta: delta),
            usesSchedule: useSchedule,
            offTimeRanges: offRanges,
            isOffTime: isOffTime,
            markerFraction: marker
        )
    }

    /// Walks active time from `now`, consuming `needed` seconds, and lands on real calendar time.
    static func scheduleCoolingDate(needed: TimeInterval, intervals: [DateInterval], now: Date, resetsAt: Date) -> Date {
        var remaining = needed
        for iv in intervals where iv.end > now {
            let lo = max(iv.start, now)
            let length = iv.end.timeIntervalSince(lo)
            if remaining <= length { return min(lo.addingTimeInterval(remaining), resetsAt) }
            remaining -= length
        }
        return resetsAt
    }

    /// Off-time ranges as calendar fractions of the window.
    static func gaps(between intervals: [DateInterval], start: Date, end: Date, duration: TimeInterval) -> [ClosedRange<Double>] {
        func fraction(_ d: Date) -> Double { clamp01(d.timeIntervalSince(start) / duration) }
        var ranges: [ClosedRange<Double>] = []
        var previousEnd = start
        for iv in intervals {
            if iv.start > previousEnd { ranges.append(fraction(previousEnd)...fraction(iv.start)) }
            previousEnd = max(previousEnd, iv.end)
        }
        if end > previousEnd { ranges.append(fraction(previousEnd)...fraction(end)) }
        return ranges
    }

    static func clamp01(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        return min(max(x, 0), 1)
    }
}
