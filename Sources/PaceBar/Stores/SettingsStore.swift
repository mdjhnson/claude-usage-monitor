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
        static let theme = "pacebar.theme"
        static let warningThreshold = "pacebar.threshold.warning"
        static let criticalThreshold = "pacebar.threshold.critical"
    }

    static let refreshRange: ClosedRange<Double> = 60...600
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
    var themePreset: ThemePreset { didSet { defaults.set(themePreset.rawValue, forKey: Key.theme) } }
    var warningThreshold: Double { didSet { defaults.set(warningThreshold, forKey: Key.warningThreshold) } }
    var criticalThreshold: Double { didSet { defaults.set(criticalThreshold, forKey: Key.criticalThreshold) } }

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
        themePreset = ThemePreset(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .default
        warningThreshold = double(Key.warningThreshold, 60, 5...95)
        criticalThreshold = double(Key.criticalThreshold, 85, 10...100)
    }

    var schedule: WorkSchedule {
        WorkSchedule(
            enabled: scheduleEnabled, activeDays: scheduleDays,
            hoursEnabled: hoursEnabled, startHour: startHour, endHour: endHour
        )
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
