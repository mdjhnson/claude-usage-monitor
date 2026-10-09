import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var store = UsageStore(settings: settings)
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(store: store, settings: settings) { [weak self] in
            self?.showSettings()
        }
        store.start()

        // Pause polling while asleep; refresh on wake.
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.handleSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.handleWake() }
            },
        ]
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(store: store, settings: settings)
        }
        settingsWindow?.show()
    }
}
