import AppKit
import Observation
import SwiftUI
import PaceBarCore

/// Owns the menu bar item and its popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: UsageStore
    private let settings: SettingsStore
    private var appearanceObservation: NSKeyValueObservation?
    private var ticker: Timer?

    init(store: UsageStore, settings: SettingsStore, openSettings: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        super.init()
        // A stable identity lets macOS and menu bar managers (Bartender, Ice) remember placement.
        statusItem.autosaveName = "io.github.mdjhnson.pacebar.status"

        let hosting = NSHostingController(rootView: PopoverView(store: store, settings: settings, openSettings: { [weak self] in
            self?.popover.performClose(nil)
            openSettings()
        }))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.toolTip = "PaceBar"
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor in self?.render() }
            }
        }

        observeAndRender()
        // Pacing drifts with time even without new data, and staleness depends on the clock.
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            store.popoverOpened()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Re-renders whenever anything the menu bar reads changes.
    private func observeAndRender() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAndRender() }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let now = Date()
        let theme = Theme.preset(settings.themePreset)

        guard let snapshot = store.snapshot else {
            let symbol = store.lastError == nil ? "gauge.with.needle" : "exclamationmark.triangle"
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PaceBar")
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel(store.lastError == nil ? "PaceBar: loading" : "PaceBar: needs attention")
            return
        }

        let windows = snapshot.usage.windows.filter { settings.menuBarWindowIDs.contains($0.id) }
        guard !windows.isEmpty else {
            let image = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "PaceBar")
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("PaceBar")
            return
        }

        let segments = windows.map { window -> MenuBarRenderer.Segment in
            let pacing = settings.pacing(for: window, now: now)
            let color = settings.monochromeMenuBar
                ? NSColor.labelColor
                : theme.tint(
                    utilization: window.bucket.utilization, pacing: pacing, mode: settings.colorMode,
                    warningAt: settings.warningThreshold, criticalAt: settings.criticalThreshold
                ).nsColor
            return .init(label: window.kind.shortLabel, value: Format.percent(window.bucket.utilization), color: color)
        }

        button.image = MenuBarRenderer.image(segments: segments, style: settings.menuBarStyle, dimmed: store.isStale(now: now))
        button.setAccessibilityLabel(
            "Claude usage: " + windows.map { "\($0.kind.title) \(Format.percent($0.bucket.utilization))" }.joined(separator: ", ")
        )
    }
}
