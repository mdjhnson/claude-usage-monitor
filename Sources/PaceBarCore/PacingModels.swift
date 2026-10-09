import Foundation

/// How far usage sits from the steady pace line.
public enum PacingZone: String, CaseIterable, Sendable {
    case chill, onTrack, warning, hot

    public var title: String {
        switch self {
        case .chill: "Chill"
        case .onTrack: "On track"
        case .warning: "Watch out"
        case .hot: "Hot"
        }
    }
}

/// A usage window reported by the API.
public enum WindowKind: Hashable, Sendable {
    /// The rolling 5 hour session.
    case session
    /// The all-models weekly limit (`seven_day`).
    case weekly
    /// A per-model weekly limit, keyed by its display name ("Sonnet", "Opus", ...).
    case weeklyModel(String)

    public static let sessionDuration: TimeInterval = 5 * 3600
    public static let weeklyDuration: TimeInterval = 7 * 24 * 3600

    public var duration: TimeInterval {
        self == .session ? Self.sessionDuration : Self.weeklyDuration
    }

    /// The workweek schedule only ever adjusts weekly windows.
    public var usesSchedule: Bool { self != .session }

    /// Stable identifier, also used as the settings key for menu bar visibility.
    public var id: String {
        switch self {
        case .session: "session"
        case .weekly: "weekly"
        case .weeklyModel(let name): "weekly." + name.lowercased()
        }
    }

    public var title: String {
        switch self {
        case .session: "5-Hour Session"
        case .weekly: "Weekly"
        case .weeklyModel(let name): "Weekly · " + name
        }
    }

    /// Short label for the menu bar.
    public var shortLabel: String {
        switch self {
        case .session: "5h"
        case .weekly: "7d"
        case .weeklyModel(let name): String(name.prefix(3))
        }
    }
}

/// The result of pacing one window at one instant. Pure value, no UI types.
public struct PacingResult: Equatable, Sendable {
    /// Utilization as reported (0 to 100, may exceed 100).
    public let actualUsage: Double
    /// Where usage "should" be if spent evenly (0 to 100).
    public let expectedUsage: Double
    /// `actualUsage - expectedUsage`.
    public let delta: Double
    public let zone: PacingZone
    /// When the pace line catches up with current usage if spending stops now. Nil unless delta > 0.
    public let coolingDate: Date?
    /// Deterministic one-liner for the zone.
    public let message: String
    /// True when the workweek schedule shaped this result.
    public let usesSchedule: Bool
    /// Off-time ranges as calendar fractions (0...1) of the window, for the hatch overlay.
    public let offTimeRanges: [ClosedRange<Double>]
    /// True when `now` falls in off time (schedule mode only).
    public let isOffTime: Bool
    /// X position (0...1) of the pace marker on the bar. In schedule mode this is calendar
    /// time so it lines up with `offTimeRanges`; otherwise it equals expected usage.
    public let markerFraction: Double
}

/// Rotating copy per zone and window type. Variants credit TokenEater (MIT), see THIRD_PARTY_NOTICES.md.
public enum PacingQuips {
    static let session: [PacingZone: [String]] = [
        .chill: ["Cool 5h", "Time to spare", "Easy session"],
        .onTrack: ["Locked in", "Session rhythm", "Right on the hour"],
        .warning: ["Session warming", "5h edging up", "Tempo creeping"],
        .hot: ["5h on fire", "Session blazing", "Burning the hour"],
    ]

    static let weekly: [PacingZone: [String]] = [
        .chill: ["Easy week", "Plenty of week", "Calm cycle"],
        .onTrack: ["Weekly cadence", "Steady week", "Marathon rhythm"],
        .warning: ["Week picking up", "Pace creeping", "Cadence edging"],
        .hot: ["Week's burning", "Cycle blazing", "Torching the week"],
    ]

    /// Picks a variant from `abs(Int(delta)) % count` so wording is stable between refreshes.
    public static func message(zone: PacingZone, kind: WindowKind, delta: Double) -> String {
        let pool = (kind == .session ? session : weekly)[zone] ?? []
        guard !pool.isEmpty else { return zone.title }
        let truncated = delta.isFinite ? Int(max(min(delta, 1e6), -1e6)) : 0
        return pool[abs(truncated) % pool.count]
    }
}
