import Foundation
import WidgetKit
import PaceBarCore

/// Shares what the popover shows with the widgets. After each refresh, and whenever a display
/// setting changes, it writes a `WidgetSnapshot` to the App Group container and asks WidgetKit
/// to reload when something visible changed. Usage values, readings and settings only.
@MainActor
final class WidgetPublisher {
    /// A changed percentage or zone reloads at most this often, which keeps PaceBar inside
    /// WidgetKit's daily reload budget at the fastest refresh interval.
    static let minReloadGap: TimeInterval = 5 * 60
    /// After a widget's refresh button, every publish reloads for this long, so the fetch it
    /// started reaches the widgets without waiting out `minReloadGap`.
    static let requestedReloadWindow: TimeInterval = 20

    /// What a widget visibly shows, to tell a real change from a refresh with the same numbers.
    private struct Visible: Equatable {
        struct Row: Equatable {
            let kind: WindowKind
            let percent: Int
            let zone: PacingZone?
        }
        let display: WidgetSnapshot.Display
        let hasError: Bool
        let rows: [Row]
    }

    private let store: UsageStore
    private let settings: SettingsStore
    private let file = WidgetSnapshotStore()
    private var lastVisible: Visible?
    private var lastResets: [WindowKind: Date?] = [:]
    private var lastReload: Date?
    private var forceReloadUntil: Date?

    init(store: UsageStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        observe()
        listenForRefreshRequests()
    }

    // MARK: Refresh button

    /// The widgets' refresh button posts a Darwin notification, since the sandboxed extension
    /// can't fetch. The publisher lives as long as the app, so the observer is never removed.
    private func listenForRefreshRequests() {
        guard let name = WidgetSnapshotStore.refreshNotificationName() else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let publisher = Unmanaged<WidgetPublisher>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in publisher.refreshRequested() }
            },
            name as CFString, nil, .deliverImmediately
        )
    }

    /// Shows what the app already has straight away, then fetches if the data is over 30 s old.
    private func refreshRequested() {
        forceReloadUntil = Date().addingTimeInterval(Self.requestedReloadWindow)
        publish()
        store.widgetRefreshRequested()
    }

    // MARK: Observation

    private func observe() {
        withObservationTracking {
            _ = store.snapshot
            _ = store.history
            _ = store.lastError
            _ = settings.theme
            _ = settings.colorMode
            _ = settings.warningThreshold
            _ = settings.criticalThreshold
            _ = settings.margin
            _ = settings.schedule
            _ = settings.refreshInterval
            _ = settings.popoverHiddenWindowIDs
            _ = settings.showUsageGraph
            _ = settings.weeklyDayMarkers
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.publish()
                self?.observe()
            }
        }
    }

    // MARK: Publishing

    private func publish() {
        guard let file, let data = store.snapshot else { return }
        let now = Date()
        let snapshot = WidgetSnapshot(
            fetchedAt: data.fetchedAt,
            refreshInterval: settings.refreshInterval,
            hasError: store.lastError != nil,
            windows: data.usage.windows
                .filter { !settings.popoverHiddenWindowIDs.contains($0.id) }
                .map { window in
                    WidgetSnapshot.Window(
                        kind: window.kind, utilization: window.bucket.utilization, resetsAt: window.bucket.resetsAt,
                        samples: UsageSample.downsampled(store.history.samples(for: window.kind), to: WidgetSnapshot.maxSamples)
                    )
                },
            display: WidgetSnapshot.Display(
                margin: settings.margin, schedule: settings.schedule, colorMode: settings.colorMode.rawValue,
                warningAt: settings.warningThreshold, criticalAt: settings.criticalThreshold,
                usageGraph: settings.showUsageGraph, weeklyDayMarkers: settings.weeklyDayMarkers.rawValue,
                theme: settings.theme.widgetColors
            )
        )
        // Best effort: the widget falls back to its last good file, dimmed once it's stale.
        guard (try? file.write(snapshot)) != nil else { return }
        if shouldReload(snapshot, now: now) {
            WidgetCenter.shared.reloadAllTimelines()
            lastReload = now
        }
    }

    /// Settings, errors and resets reload at once. Other changes wait out `minReloadGap`, and
    /// `maxReloadGap` brings the graphs up to date even when the numbers hold still.
    private func shouldReload(_ snapshot: WidgetSnapshot, now: Date) -> Bool {
        let visible = Visible(
            display: snapshot.display,
            hasError: snapshot.hasError,
            rows: snapshot.windows.map {
                .init(kind: $0.kind, percent: Int($0.utilization.rounded()), zone: snapshot.pacing(for: $0, now: now)?.zone)
            }
        )
        let resets = Dictionary(snapshot.windows.map { ($0.kind, $0.resetsAt) }, uniquingKeysWith: { first, _ in first })
        // Compared with what the widget last reloaded with, so a change held back by the gap
        // still goes out with a later refresh.
        let reload = (forceReloadUntil.map { now < $0 } ?? false) || needsReload(visible, resets: resets, now: now)
        if reload {
            lastVisible = visible
            lastResets = resets
        }
        return reload
    }

    private func needsReload(_ visible: Visible, resets: [WindowKind: Date?], now: Date) -> Bool {
        guard let last = lastVisible, let lastReload else { return true }
        let newCycle = resets.contains { kind, resetsAt in
            lastResets[kind].map { ResetCycle.isNew(old: $0, new: resetsAt) } ?? true
        }
        if visible.display != last.display || visible.hasError != last.hasError
            || visible.rows.map(\.kind) != last.rows.map(\.kind) || newCycle {
            return true
        }
        let gap = now.timeIntervalSince(lastReload)
        return gap >= WidgetSnapshot.maxReloadGap || (visible != last && gap >= Self.minReloadGap)
    }
}
