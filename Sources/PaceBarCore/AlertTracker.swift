import Foundation

/// One window as the alert tracker sees it after a refresh.
public struct AlertInput: Equatable, Sendable {
    public let kind: WindowKind
    public let utilization: Double
    public let resetsAt: Date?
    /// Nil when the window has no reset time, so no pacing.
    public let zone: PacingZone?
    public let coolingDate: Date?
    public let delta: Double?

    public init(kind: WindowKind, utilization: Double, resetsAt: Date?, zone: PacingZone?, coolingDate: Date? = nil, delta: Double? = nil) {
        self.kind = kind
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.zone = zone
        self.coolingDate = coolingDate
        self.delta = delta
    }
}

public enum UsageLevel: Int, Comparable, Sendable {
    case normal, warning, critical

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    static func of(_ utilization: Double, warningAt: Double, criticalAt: Double) -> Self {
        if utilization >= criticalAt { return .critical }
        if utilization >= warningAt { return .warning }
        return .normal
    }
}

public enum AlertEvent: Equatable, Sendable {
    /// Usage crossed the warning or critical threshold for the first time this cycle.
    case threshold(AlertInput, UsageLevel)
    /// The window entered the Hot zone.
    case runningHot(AlertInput)
    /// The window is back on track or under pace after a Hot alert.
    case backOnPace(AlertInput)
}

/// Decides which alerts a refresh should raise. Memory only: nothing is persisted.
///
/// - The first time a window is seen (including after launch) its state is recorded silently,
///   so restarting PaceBar never repeats alerts that already went out.
/// - A new cycle starts only when the reset time actually moves, not when the gauge eases off
///   as time catches up with usage.
/// - Each threshold alerts once per cycle. Hot alerts once, then re-arms only after the window
///   is back on track or under pace, which also announces itself. The gap between Hot and On
///   track is a whole margin wide, so a window hovering at a boundary can't flap.
public struct AlertTracker: Sendable {
    struct WindowState: Sendable {
        var resetsAt: Date?
        var level: UsageLevel
        var hotAlerted: Bool
    }

    private var states: [String: WindowState] = [:]

    public init() {}

    public mutating func update(_ windows: [AlertInput], warningAt: Double, criticalAt: Double) -> [AlertEvent] {
        var events: [AlertEvent] = []
        var next: [String: WindowState] = [:]

        for window in windows {
            let level = UsageLevel.of(window.utilization, warningAt: warningAt, criticalAt: criticalAt)
            let isHot = window.zone == .hot

            guard var state = states[window.kind.id] else {
                next[window.kind.id] = WindowState(resetsAt: window.resetsAt, level: level, hotAlerted: isHot)
                continue
            }

            if ResetCycle.isNew(old: state.resetsAt, new: window.resetsAt) {
                state = WindowState(resetsAt: window.resetsAt, level: .normal, hotAlerted: false)
            }

            if level > state.level {
                events.append(.threshold(window, level))
                state.level = level
            }

            if isHot && !state.hotAlerted {
                events.append(.runningHot(window))
                state.hotAlerted = true
            } else if state.hotAlerted, let zone = window.zone, zone == .onTrack || zone == .chill {
                events.append(.backOnPace(window))
                state.hotAlerted = false
            }

            next[window.kind.id] = state
        }

        // Windows that stopped being reported are forgotten; they start silently if they return.
        states = next
        return events
    }
}

/// A reminder scheduled ahead of a reset.
public struct ResetReminder: Equatable, Sendable {
    public let kind: WindowKind
    public let resetsAt: Date
    public let fireAt: Date
    public let lead: TimeInterval
}

public enum ResetReminderPlanner {
    /// One reminder per window whose reset is far enough away for its lead time.
    /// `lead` gives how long before a window's reset to remind; nil or 0 means off.
    public static func plan(_ windows: [AlertInput], lead: (WindowKind) -> TimeInterval?, now: Date) -> [ResetReminder] {
        windows.compactMap { window in
            guard let resetsAt = window.resetsAt, let lead = lead(window.kind), lead > 0 else { return nil }
            let fireAt = resetsAt.addingTimeInterval(-lead)
            guard fireAt > now else { return nil }
            return ResetReminder(kind: window.kind, resetsAt: resetsAt, fireAt: fireAt, lead: lead)
        }
    }
}
