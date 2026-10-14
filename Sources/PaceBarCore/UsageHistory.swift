import Foundation

public struct UsageSample: Equatable, Sendable {
    public let date: Date
    public let utilization: Double

    public init(date: Date, utilization: Double) {
        self.date = date
        self.utilization = utilization
    }
}

/// Usage readings for each window's current cycle, for the graph on each card. Memory only:
/// it starts empty at launch and nothing is written to disk.
public struct UsageHistory: Equatable, Sendable {
    struct Series: Equatable, Sendable {
        var resetsAt: Date?
        var samples: [UsageSample]
    }

    /// A week at the fastest refresh is about 10,000 readings. Past this, every other one is
    /// dropped, which keeps the shape while bounding memory.
    static let maxSamples = 2_000

    private var series: [String: Series] = [:]

    public init() {}

    public func samples(for kind: WindowKind) -> [UsageSample] {
        series[kind.id]?.samples ?? []
    }

    public mutating func record(_ windows: [UsageWindow], at date: Date) {
        for window in windows {
            let id = window.kind.id
            var entry = series[id] ?? Series(resetsAt: window.bucket.resetsAt, samples: [])
            if ResetCycle.isNew(old: entry.resetsAt, new: window.bucket.resetsAt) {
                entry = Series(resetsAt: window.bucket.resetsAt, samples: [])
            }
            if let last = entry.samples.last, date <= last.date { continue }
            entry.samples.append(UsageSample(date: date, utilization: window.bucket.utilization))
            if entry.samples.count > Self.maxSamples {
                entry.samples = entry.samples.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
            }
            series[id] = entry
        }
    }
}

/// A point on a graph: `x` is the fraction of the window's calendar time, `y` is percent.
public struct GraphPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

extension PacingCalculator {
    /// The steady-pace line across the whole window, as the vertices of a polyline. Without a
    /// workweek schedule it's the diagonal; with one it climbs during active time and stays flat
    /// during off time, matching how expected usage is computed.
    public static func paceCurve(resetsAt: Date, kind: WindowKind, schedule: WorkSchedule, calendar: Calendar) -> [GraphPoint] {
        let duration = kind.duration
        let start = resetsAt.addingTimeInterval(-duration)
        guard kind.usesSchedule && schedule.isRestricting else {
            return [GraphPoint(x: 0, y: 0), GraphPoint(x: 1, y: 100)]
        }
        let intervals = schedule.activeIntervals(from: start, to: resetsAt, calendar: calendar)
        let total = intervals.reduce(0) { $0 + $1.duration }
        guard total > 0 else { return [GraphPoint(x: 0, y: 0), GraphPoint(x: 1, y: 0)] }

        func x(_ date: Date) -> Double { clamp01(date.timeIntervalSince(start) / duration) }
        var points = [GraphPoint(x: 0, y: 0)]
        var elapsed: TimeInterval = 0
        for iv in intervals {
            points.append(GraphPoint(x: x(iv.start), y: elapsed / total * 100))
            elapsed += iv.duration
            points.append(GraphPoint(x: x(iv.end), y: elapsed / total * 100))
        }
        points.append(GraphPoint(x: 1, y: 100))
        return points
    }
}

/// Lookups for hovering a graph.
public enum GraphMath {
    /// The index of the point whose `x` is closest to `x`. Ties go to the earlier point.
    public static func nearestIndex(in points: [GraphPoint], toX x: Double) -> Int? {
        points.indices.min { abs(points[$0].x - x) < abs(points[$1].x - x) }
    }

    /// The polyline's value at `x`, by linear interpolation. Clamped to the first and last points.
    public static func value(of curve: [GraphPoint], at x: Double) -> Double? {
        guard let first = curve.first, let last = curve.last else { return nil }
        if x <= first.x { return first.y }
        for (a, b) in zip(curve, curve.dropFirst()) where a.x <= x && x <= b.x {
            return b.x == a.x ? b.y : a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
        }
        return last.y
    }
}

/// One calendar day's column on a graph, as fractions of the window's calendar time.
public struct GraphDay: Equatable, Sendable {
    public let start: Double
    public let end: Double
    /// When this column starts: the window's start for the first, local midnight for the rest.
    public let date: Date

    public init(start: Double, end: Double, date: Date) {
        self.start = start
        self.end = end
        self.date = date
    }
}

extension GraphMath {
    /// Splits a window at local midnights. The first and last columns may be partial days.
    /// Midnights come from the calendar, so 23- and 25-hour DST days get their true widths.
    public static func days(from start: Date, to end: Date, calendar: Calendar) -> [GraphDay] {
        guard end > start else { return [] }
        let span = end.timeIntervalSince(start)
        func x(_ date: Date) -> Double { min(max(date.timeIntervalSince(start) / span, 0), 1) }

        var days: [GraphDay] = []
        var dayStart = start
        // Bounded so a broken calendar can't loop forever; a weekly window has 8 columns at most.
        while dayStart < end, days.count < 64 {
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dayStart)) ?? end
            let dayEnd = min(midnight, end)
            guard dayEnd > dayStart else { break }
            days.append(GraphDay(start: x(dayStart), end: x(dayEnd), date: dayStart))
            dayStart = dayEnd
        }
        return days
    }
}
