import Foundation
import Observation
import PaceBarCore

enum ColorMode: String, CaseIterable, Identifiable {
    case pacing, threshold
    var id: String { rawValue }
    var title: String { self == .pacing ? "Pacing zone" : "Usage threshold" }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case classic, pill
    var id: String { rawValue }
    var title: String { self == .classic ? "Classic" : "Pill" }
}

/// What the menu bar shows after each percentage.
enum MenuBarExtra: String, CaseIterable, Identifiable {
    case none, countdown, arrows, fireAndIce
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Nothing"
        case .countdown: "Reset countdown"
        case .arrows: "Pace arrows"
        case .fireAndIce: "Fire & ice"
        }
    }
}

/// How weekly graphs mark the days.
enum WeeklyDayMarkers: String, CaseIterable, Identifiable {
    case off, lines, linesAndNames
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .lines: "Lines"
        case .linesAndNames: "Lines and day names"
        }
    }
}

/// Non-sensitive preferences only. Nothing here may ever hold a token or response data.
@MainActor @Observable
final class SettingsStore {
    /// Every key this app writes. `defaults delete io.github.mdjhnson.pacebar` removes them all.
    enum Key {
        static let margin = "pacebar.margin"
        static let scheduleEnabled = "pacebar.schedule.enabled"
        static let scheduleDays = "pacebar.schedule.days"
        static let hoursEnabled = "pacebar.schedule.hoursEnabled"
        static let startHour = "pacebar.schedule.startHour"
        static let endHour = "pacebar.schedule.endHour"
        static let refreshInterval = "pacebar.refreshInterval"
        static let menuBarWindows = "pacebar.menuBar.windows"
        static let popoverHidden = "pacebar.popover.hiddenWindows"
        static let menuBarStyle = "pacebar.menuBar.style"
        static let colorMode = "pacebar.menuBar.colorMode"
        static let monochrome = "pacebar.menuBar.monochrome"
        static let menuBarExtra = "pacebar.menuBar.extra"
        static let theme = "pacebar.theme"
        static let customTheme = "pacebar.theme.custom"
        static let usageGraph = "pacebar.popover.usageGraph"
        static let weeklyDayMarkers = "pacebar.popover.weeklyDayMarkers"
        static let warningThreshold = "pacebar.threshold.warning"
        static let criticalThreshold = "pacebar.threshold.critical"
        static let notifyUsage = "pacebar.notify.usage"
        static let notifyPace = "pacebar.notify.pace"
        static let sessionReminder = "pacebar.notify.sessionReminderMinutes"
        static let weeklyReminder = "pacebar.notify.weeklyReminderMinutes"
    }

    static let refreshRange: ClosedRange<Double> = 60...600
    /// Reminder lead times in minutes; 0 is off.
    static let sessionReminderChoices = [0, 5, 10, 15, 30, 60]
    static let weeklyReminderChoices = [0, 30, 60, 120, 180, 360]
    static let defaultRefresh: Double = 180

    @ObservationIgnored private let defaults: UserDefaults

    var margin: Double { didSet { defaults.set(margin, forKey: Key.margin) } }
    var scheduleEnabled: Bool { didSet { defaults.set(scheduleEnabled, forKey: Key.scheduleEnabled) } }
    var scheduleDays: Set<Int> { didSet { defaults.set(scheduleDays.sorted(), forKey: Key.scheduleDays) } }
    var hoursEnabled: Bool { didSet { defaults.set(hoursEnabled, forKey: Key.hoursEnabled) } }
    var startHour: Int { didSet { defaults.set(startHour, forKey: Key.startHour) } }
    var endHour: Int { didSet { defaults.set(endHour, forKey: Key.endHour) } }
    var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) } }
    var menuBarWindowIDs: Set<String> { didSet { defaults.set(menuBarWindowIDs.sorted(), forKey: Key.menuBarWindows) } }
    var popoverHiddenWindowIDs: Set<String> { didSet { defaults.set(popoverHiddenWindowIDs.sorted(), forKey: Key.popoverHidden) } }
    var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: Key.menuBarStyle) } }
    var colorMode: ColorMode { didSet { defaults.set(colorMode.rawValue, forKey: Key.colorMode) } }
    var monochromeMenuBar: Bool { didSet { defaults.set(monochromeMenuBar, forKey: Key.monochrome) } }
    var menuBarExtra: MenuBarExtra { didSet { defaults.set(menuBarExtra.rawValue, forKey: Key.menuBarExtra) } }
    var themePreset: ThemePreset { didSet { defaults.set(themePreset.rawValue, forKey: Key.theme) } }
    /// The custom theme's colors, stored as "#RRGGBB" strings keyed by token name.
    var customColors: [Theme.Token: ThemeColor] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: customColors.map { ($0.key.rawValue, $0.value.hexString) })
            defaults.set(stored, forKey: Key.customTheme)
        }
    }
    var showUsageGraph: Bool { didSet { defaults.set(showUsageGraph, forKey: Key.usageGraph) } }
    var weeklyDayMarkers: WeeklyDayMarkers { didSet { defaults.set(weeklyDayMarkers.rawValue, forKey: Key.weeklyDayMarkers) } }
    var warningThreshold: Double { didSet { defaults.set(warningThreshold, forKey: Key.warningThreshold) } }
    var criticalThreshold: Double { didSet { defaults.set(criticalThreshold, forKey: Key.criticalThreshold) } }
    var notifyUsage: Bool { didSet { defaults.set(notifyUsage, forKey: Key.notifyUsage) } }
    var notifyPace: Bool { didSet { defaults.set(notifyPace, forKey: Key.notifyPace) } }
    var sessionReminderMinutes: Int { didSet { defaults.set(sessionReminderMinutes, forKey: Key.sessionReminder) } }
    var weeklyReminderMinutes: Int { didSet { defaults.set(weeklyReminderMinutes, forKey: Key.weeklyReminder) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = WorkSchedule.default

        func double(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            guard let v = defaults.object(forKey: key) as? Double, v.isFinite else { return fallback }
            return min(max(v, range.lowerBound), range.upperBound)
        }
        func int(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            guard let v = defaults.object(forKey: key) as? Int else { return fallback }
            return min(max(v, range.lowerBound), range.upperBound)
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }

        margin = double(Key.margin, PacingCalculator.defaultMargin, PacingCalculator.marginRange).rounded()
        scheduleEnabled = bool(Key.scheduleEnabled, d.enabled)
        // An empty stored set is meaningful (all days, see WorkSchedule.effectiveDays); only a
        // missing key falls back to Mon-Fri.
        let days = (defaults.array(forKey: Key.scheduleDays) as? [Int]).map { Set($0.filter { (1...7).contains($0) }) }
        scheduleDays = days ?? d.activeDays
        hoursEnabled = bool(Key.hoursEnabled, d.hoursEnabled)
        startHour = int(Key.startHour, d.startHour, 0...23)
        endHour = int(Key.endHour, d.endHour, 1...24)
        refreshInterval = double(Key.refreshInterval, Self.defaultRefresh, Self.refreshRange)
        menuBarWindowIDs = Set(defaults.stringArray(forKey: Key.menuBarWindows) ?? ["session", "weekly"])
        popoverHiddenWindowIDs = Set(defaults.stringArray(forKey: Key.popoverHidden) ?? [])
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: Key.menuBarStyle) ?? "") ?? .classic
        colorMode = ColorMode(rawValue: defaults.string(forKey: Key.colorMode) ?? "") ?? .pacing
        monochromeMenuBar = bool(Key.monochrome, false)
        menuBarExtra = MenuBarExtra(rawValue: defaults.string(forKey: Key.menuBarExtra) ?? "") ?? .none
        themePreset = ThemePreset(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .default
        // Unknown tokens and malformed values are dropped; missing ones fall back to Default.
        let stored = defaults.dictionary(forKey: Key.customTheme) as? [String: String] ?? [:]
        customColors = stored.reduce(into: [:]) { colors, entry in
            guard let token = Theme.Token(rawValue: entry.key), let hex = HexColor.parse(entry.value) else { return }
            colors[token] = ThemeColor(hex: hex)
        }
        showUsageGraph = bool(Key.usageGraph, true)
        weeklyDayMarkers = WeeklyDayMarkers(rawValue: defaults.string(forKey: Key.weeklyDayMarkers) ?? "") ?? .linesAndNames
        warningThreshold = double(Key.warningThreshold, 60, 5...95)
        criticalThreshold = double(Key.criticalThreshold, 85, 10...100)
        notifyUsage = bool(Key.notifyUsage, false)
        notifyPace = bool(Key.notifyPace, false)
        func choice(_ key: String, _ choices: [Int]) -> Int {
            let v = defaults.object(forKey: key) as? Int ?? 0
            return choices.contains(v) ? v : 0
        }
        sessionReminderMinutes = choice(Key.sessionReminder, Self.sessionReminderChoices)
        weeklyReminderMinutes = choice(Key.weeklyReminder, Self.weeklyReminderChoices)
    }

    /// The theme in use, including the person's own colors when Custom is chosen.
    var theme: Theme {
        themePreset == .custom ? .custom(customColors) : .preset(themePreset)
    }

    /// Chooses a theme. A first switch to Custom starts from the theme that was showing.
    func selectTheme(_ preset: ThemePreset) {
        if preset == .custom && customColors.isEmpty { customColors = theme.colors }
        themePreset = preset
    }

    /// Replaces every custom color with a built-in preset's.
    func resetCustomColors(to preset: ThemePreset) {
        customColors = Theme.preset(preset).colors
    }

    var anyNotificationsOn: Bool {
        notifyUsage || notifyPace || sessionReminderMinutes > 0 || weeklyReminderMinutes > 0
    }

    /// How long before a reset to remind. Only the session and the all-models weekly limit get
    /// reminders, so per-model limits don't double them up.
    func reminderLead(for kind: WindowKind) -> TimeInterval? {
        switch kind {
        case .session: sessionReminderMinutes > 0 ? TimeInterval(sessionReminderMinutes * 60) : nil
        case .weekly: weeklyReminderMinutes > 0 ? TimeInterval(weeklyReminderMinutes * 60) : nil
        case .weeklyModel: nil
        }
    }

    var schedule: WorkSchedule {
        WorkSchedule(
            enabled: scheduleEnabled, activeDays: scheduleDays,
            hoursEnabled: hoursEnabled, startHour: startHour, endHour: endHour
        )
    }

    /// The steady-pace line for a window's graph, or nil when the API gave no reset time.
    func paceCurve(for window: UsageWindow) -> [GraphPoint]? {
        guard let resetsAt = window.bucket.resetsAt else { return nil }
        return PacingCalculator.paceCurve(resetsAt: resetsAt, kind: window.kind, schedule: schedule, calendar: .current)
    }

    /// Pacing for one window at `now`, or nil when the API gave no reset time.
    func pacing(for window: UsageWindow, now: Date) -> PacingResult? {
        guard let resetsAt = window.bucket.resetsAt else { return nil }
        return PacingCalculator.calculate(
            utilization: window.bucket.utilization, resetsAt: resetsAt, kind: window.kind,
            margin: margin, schedule: schedule, now: now, calendar: .current
        )
    }
}
