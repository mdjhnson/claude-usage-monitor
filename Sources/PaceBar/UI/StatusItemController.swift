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

    /// - Parameter openSettings: opens Settings at a tab, or at the last one shown when nil.
    init(store: UsageStore, settings: SettingsStore, updates: UpdateChecker, openSettings: @escaping (SettingsView.Pane?) -> Void) {
        self.store = store
        self.settings = settings
        super.init()
        // A stable identity lets macOS and menu bar managers (Bartender, Ice) remember placement.
        statusItem.autosaveName = "io.github.mdjhnson.pacebar.status"

        let hosting = NSHostingController(rootView: PopoverView(store: store, settings: settings, updates: updates) { [weak self] pane in
            self?.popover.performClose(nil)
            openSettings(pane)
        })
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
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    /// Also used when a notification is clicked.
    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        store.popoverOpened()
        // Without this the previously active app keeps keyboard focus, so ⌘Q would quit it.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
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
        let theme = settings.theme

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
            return .init(
                label: window.kind.shortLabel, value: Format.percent(window.bucket.utilization), color: color,
                accessory: accessory(for: window, pacing: pacing, theme: theme, now: now)
            )
        }

        button.image = MenuBarRenderer.image(segments: segments, style: settings.menuBarStyle, dimmed: store.isStale(now: now))
        button.setAccessibilityLabel("Claude usage: " + windows.map { window in
            var text = "\(window.kind.title) \(Format.percent(window.bucket.utilization))"
            switch settings.menuBarExtra {
            case .none: break
            case .countdown:
                if let resetsAt = window.bucket.resetsAt { text += ", " + Format.resetCountdown(kind: window.kind, resetsAt: resetsAt, now: now) }
            case .arrows, .fireAndIce:
                if let zone = settings.pacing(for: window, now: now)?.zone { text += ", " + zone.title.lowercased() }
            }
            return text
        }.joined(separator: "; "))
    }

    /// Fire & ice uses fixed colors so the joke reads in every theme: ice blue, amber, red.
    static let ice = NSColor(srgbRed: 0x64 / 255, green: 0xD2 / 255, blue: 1, alpha: 1)
    static let ember = NSColor(srgbRed: 1, green: 0x95 / 255, blue: 0, alpha: 1)
    static let fire = NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)

    /// What follows the percentage. On track gets no symbol, so one only appears when it means something.
    private func accessory(for window: UsageWindow, pacing: PacingResult?, theme: Theme, now: Date) -> MenuBarRenderer.Accessory? {
        let mono = settings.monochromeMenuBar
        switch settings.menuBarExtra {
        case .none:
            return nil
        case .countdown:
            guard let resetsAt = window.bucket.resetsAt, resetsAt > now else { return nil }
            return .text(Format.compactDuration(resetsAt.timeIntervalSince(now)))
        case .arrows:
            guard let zone = pacing?.zone else { return nil }
            let color = mono ? NSColor.labelColor : theme.zone(zone).nsColor
            switch zone {
            case .chill: return .symbol(name: "chevron.down", color: color)
            case .onTrack: return nil
            case .warning: return .symbol(name: "chevron.up", color: color)
            case .hot: return .symbol(name: "chevron.up.2", color: color)
            }
        case .fireAndIce:
            guard let zone = pacing?.zone else { return nil }
            switch zone {
            case .chill: return .symbol(name: "snowflake", color: mono ? .labelColor : Self.ice)
            case .onTrack: return nil
            case .warning: return .symbol(name: "flame", color: mono ? .labelColor : Self.ember)
            case .hot: return .symbol(name: "flame.fill", color: mono ? .labelColor : Self.fire)
            }
        }
    }
}
