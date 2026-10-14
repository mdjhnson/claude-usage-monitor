import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var store = UsageStore(settings: settings)
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var notifier: Notifier?
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        statusItem = StatusItemController(store: store, settings: settings) { [weak self] in
            self?.showSettings()
        }
        notifier = Notifier(store: store, settings: settings) { [weak self] in
            self?.statusItem?.showPopover()
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
        notifier?.removeReminders()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    /// Never drawn (PaceBar is a menu bar agent), but it routes the standard shortcuts while
    /// the popover or Settings is frontmost: ⌘Q, ⌘, and ⌘W, plus copy and paste in text.
    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PaceBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let main = NSMenu()
        for (title, submenu) in [("PaceBar", appMenu), ("Edit", editMenu), ("Window", windowMenu)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }

    @objc private func openSettings() {
        statusItem?.closePopover()
        showSettings()
    }

    private func showSettings() {
        if settingsWindow == nil {
            guard let notifier else { return }
            settingsWindow = SettingsWindowController(store: store, settings: settings, notifier: notifier)
        }
        settingsWindow?.show()
    }
}
