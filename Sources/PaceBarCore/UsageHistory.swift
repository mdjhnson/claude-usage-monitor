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
