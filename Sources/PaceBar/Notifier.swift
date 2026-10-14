import AppKit
import Observation
import UserNotifications
import PaceBarCore

/// Turns refreshes into local notifications through `UserNotifications`, the only notification
/// API PaceBar uses. Everything it tracks lives in memory; nothing is written to disk.
@MainActor @Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// True when macOS has notifications turned off for PaceBar.
    private(set) var isDenied = false

    @ObservationIgnored private let store: UsageStore
    @ObservationIgnored private let settings: SettingsStore
    /// Nil when running unbundled (`swift run`), where the notification center isn't available.
    @ObservationIgnored private let center: UNUserNotificationCenter?
    @ObservationIgnored private var tracker = AlertTracker()
    @ObservationIgnored private var lastFetchedAt: Date?
    @ObservationIgnored private let onOpen: () -> Void

    static let reminderPrefix = "pacebar.reset."

    init(store: UsageStore, settings: SettingsStore, onOpen: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.onOpen = onOpen
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        center?.delegate = self
        observeSnapshot()
        observeSettings()
        if settings.anyNotificationsOn { requestAuthorization() }
    }

    // MARK: Authorization

    /// Asks once; macOS remembers the answer and later calls return it without a prompt.
    func requestAuthorization() {
        guard let center else { return }
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        }
    }

    func refreshAuthorization() async {
        guard let center else { return }
        isDenied = await center.notificationSettings().authorizationStatus == .denied
    }

    // MARK: Observation

    private func observeSnapshot() {
        withObservationTracking {
            _ = store.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.evaluate()
                self?.observeSnapshot()
            }
        }
    }

    /// Reminder choices change what's scheduled even without new data.
    private func observeSettings() {
        withObservationTracking {
            _ = settings.sessionReminderMinutes
            _ = settings.weeklyReminderMinutes
            _ = settings.popoverHiddenWindowIDs
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleReminders(now: Date())
                self?.observeSettings()
            }
        }
    }

    // MARK: Alerts

    private func inputs(now: Date) -> [AlertInput] {
        guard let snapshot = store.snapshot else { return [] }
        return snapshot.usage.windows
            .filter { !settings.popoverHiddenWindowIDs.contains($0.id) }
            .map { window in
                let pacing = settings.pacing(for: window, now: now)
                return AlertInput(
                    kind: window.kind, utilization: window.bucket.utilization, resetsAt: window.bucket.resetsAt,
                    zone: pacing?.zone, coolingDate: pacing?.coolingDate, delta: pacing?.delta
                )
            }
    }

    /// Runs once per new snapshot. The tracker runs even with alerts off, so turning them on
    /// later never releases a backlog.
    private func evaluate() {
        guard let fetchedAt = store.snapshot?.fetchedAt, fetchedAt != lastFetchedAt else { return }
        lastFetchedAt = fetchedAt
        let now = Date()
        let events = tracker.update(inputs(now: now), warningAt: settings.warningThreshold, criticalAt: settings.criticalThreshold)
        for event in events {
            switch event {
            case .threshold where settings.notifyUsage, .runningHot where settings.notifyPace, .backOnPace where settings.notifyPace:
                post(event, now: now)
            default:
                break
            }
        }
        scheduleReminders(now: now)
    }

    private func post(_ event: AlertEvent, now: Date) {
        let content = UNMutableNotificationContent()
        let window: AlertInput
        let tag: String
        switch event {
        case .threshold(let w, let level):
            window = w
            tag = "usage"
            content.title = "\(w.kind.title) at \(Format.percent(w.utilization))"
            let lead = level == .critical ? "Close to the limit." : "Past \(Int(settings.warningThreshold))%, so pace yourself."
            content.body = [lead, Self.resetSentence(w, now: now)].compactMap { $0 }.joined(separator: " ")
        case .runningHot(let w):
            window = w
            tag = "pace"
            content.title = "Running hot: \(w.kind.title)"
            let ahead = w.delta.map { "\(Format.signedPercent($0)) ahead of a steady pace." } ?? "Ahead of a steady pace."
            let cooling = w.coolingDate.map { Format.cooling($0, now: now) + " if you ease off." }
            content.body = [ahead, cooling].compactMap { $0 }.joined(separator: " ")
        case .backOnPace(let w):
            window = w
            tag = "pace"
            content.title = "Back on pace: \(w.kind.title)"
            content.body = w.zone == .chill
                ? "You're under pace now, so there's room to ramp up."
                : "You're within ±\(Int(settings.margin))% of a steady pace again."
        }
        content.sound = .default
        content.threadIdentifier = window.kind.id
        // One notification per window and kind: a newer one replaces the older in Notification Center.
        add(UNNotificationRequest(identifier: "pacebar.\(tag).\(window.kind.id)", content: content, trigger: nil))
    }

    /// "Resets in 2h 14m (3:45 PM)." for the session, "Resets Tue 3:00 PM." for weekly limits.
    static func resetSentence(_ window: AlertInput, now: Date) -> String? {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        let countdown = Format.resetCountdown(kind: window.kind, resetsAt: resetsAt, now: now)
        let sentence = countdown.prefix(1).uppercased() + countdown.dropFirst()
        return window.kind == .session ? "\(sentence) (\(Format.time(resetsAt)))." : "\(sentence)."
    }

    // MARK: Reminders

    /// Replaces PaceBar's pending reminders with the current plan. Requests that already match
    /// are re-added under the same identifier, which macOS treats as a replacement.
    private func scheduleReminders(now: Date) {
        guard let center else { return }
        let plan = ResetReminderPlanner.plan(inputs(now: now), lead: settings.reminderLead(for:), now: now)
        let planned = Set(plan.map { Self.reminderPrefix + $0.kind.id })
        Task {
            let stale = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.reminderPrefix) && !planned.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = "\(reminder.kind.title) resets in \(Self.lead(reminder.lead))"
            content.body = reminder.kind == .session
                ? "At \(Format.time(reminder.resetsAt))."
                : "At \(Format.weekdayTime(reminder.resetsAt))."
            content.sound = .default
            content.threadIdentifier = reminder.kind.id
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(reminder.fireAt.timeIntervalSince(now), 1), repeats: false)
            add(UNNotificationRequest(identifier: Self.reminderPrefix + reminder.kind.id, content: content, trigger: trigger))
        }
    }

    /// Removes pending reminders, so none fire after PaceBar quits.
    func removeReminders() {
        guard let center else { return }
        let ids = [WindowKind.session, .weekly].map { Self.reminderPrefix + $0.id }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// "15 min", "1 hour", "6 hours".
    static func lead(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    private func add(_ request: UNNotificationRequest) {
        center?.add(request) { _ in }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show banners even while the popover has made PaceBar the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Clicking a notification opens the popover.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { onOpen() }
    }
}
