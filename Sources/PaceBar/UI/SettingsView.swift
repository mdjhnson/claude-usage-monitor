import AppKit
import ServiceManagement
import SwiftUI
import PaceBarCore

/// A preferences window with toolbar tabs, one short SwiftUI form per tab.
/// The window resizes to fit whichever tab is selected.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(store: UsageStore, settings: SettingsStore) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for pane in SettingsView.Pane.allCases {
            let hosting = NSHostingController(rootView: SettingsView(pane: pane, store: store, settings: settings))
            hosting.sizingOptions = [.preferredContentSize]
            hosting.title = pane.title
            let item = NSTabViewItem(viewController: hosting)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    enum Pane: CaseIterable {
        case pacing, menuBar, appearance, general

        var title: String {
            switch self {
            case .pacing: "Pacing"
            case .menuBar: "Menu Bar"
            case .appearance: "Appearance"
            case .general: "General"
            }
        }

        var symbol: String {
            switch self {
            case .pacing: "gauge.with.needle"
            case .menuBar: "menubar.rectangle"
            case .appearance: "paintpalette"
            case .general: "gearshape"
            }
        }
    }

    let pane: Pane
    let store: UsageStore
    @Bindable var settings: SettingsStore

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchStatus = SMAppService.mainApp.status
    @State private var launchError: String?
    @State private var copied = false

    var body: some View {
        Form {
            switch pane {
            case .pacing:
                pacingSection
            case .menuBar:
                windowsSection
                menuBarSection
            case .appearance:
                appearanceSection
            case .general:
                generalSection
                diagnosticsSection
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: settings.refreshInterval) { store.reschedule() }
    }

    // MARK: Pacing

    private var pacingSection: some View {
        Section {
            LabeledContent("Margin") {
                HStack {
                    Slider(value: $settings.margin, in: PacingCalculator.marginRange, step: 1)
                    Text("±\(Int(settings.margin))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Toggle("Workweek pacing", isOn: $settings.scheduleEnabled)
            if settings.scheduleEnabled {
                LabeledContent("Active days") { DayPicker(selection: $settings.scheduleDays) }
                Toggle("Active hours only", isOn: $settings.hoursEnabled)
                if settings.hoursEnabled {
                    Picker("From", selection: startHour) {
                        ForEach(0..<24, id: \.self) { Text(Format.hour($0)).tag($0) }
                    }
                    Picker("Until", selection: $settings.endHour) {
                        ForEach((settings.startHour + 1)...24, id: \.self) { Text(Format.hour($0)).tag($0) }
                    }
                }
            }
        } header: {
            Text("Pacing")
        } footer: {
            Text("Within ±margin of the steady pace counts as on track. Workweek pacing applies to weekly limits only; off days and hours don't advance the expected pace.")
                .foregroundStyle(.secondary)
        }
    }

    /// Keeps the end hour after the start hour.
    private var startHour: Binding<Int> {
        Binding {
            settings.startHour
        } set: { newValue in
            settings.startHour = newValue
            if settings.endHour <= newValue { settings.endHour = min(newValue + 1, 24) }
        }
    }

    // MARK: Windows

    private var windowsSection: some View {
        Section {
            ForEach(availableWindows, id: \.id) { kind in
                HStack {
                    Text(kind.title)
                    Spacer()
                    Toggle("Menu bar", isOn: menuBarBinding(for: kind.id))
                        .toggleStyle(.checkbox)
                    Toggle("Popover", isOn: popoverBinding(for: kind.id))
                        .toggleStyle(.checkbox)
                }
            }
        } header: {
            Text("Windows")
        } footer: {
            Text("Choose where each usage limit appears. Per-model limits (like Fable) show up here once your account reports them.")
                .foregroundStyle(.secondary)
        }
    }

    private func popoverBinding(for id: String) -> Binding<Bool> {
        Binding {
            !settings.popoverHiddenWindowIDs.contains(id)
        } set: { shown in
            if shown { settings.popoverHiddenWindowIDs.remove(id) } else { settings.popoverHiddenWindowIDs.insert(id) }
        }
    }

    // MARK: Menu bar

    private var menuBarSection: some View {
        Section("Menu bar") {
            Picker("Style", selection: $settings.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Color by", selection: $settings.colorMode) {
                ForEach(ColorMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Monochrome menu bar", isOn: $settings.monochromeMenuBar)
        }
    }

    /// Session and weekly always, plus any per-model windows the last response included.
    private var availableWindows: [WindowKind] {
        var kinds: [WindowKind] = [.session, .weekly]
        for window in store.snapshot?.usage.windows ?? [] where !kinds.contains(window.kind) {
            kinds.append(window.kind)
        }
        return kinds
    }

    private func menuBarBinding(for id: String) -> Binding<Bool> {
        Binding {
            settings.menuBarWindowIDs.contains(id)
        } set: { on in
            if on { settings.menuBarWindowIDs.insert(id) } else { settings.menuBarWindowIDs.remove(id) }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $settings.themePreset) {
                ForEach(ThemePreset.allCases) { preset in
                    HStack(spacing: 6) {
                        ThemeSwatch(theme: .preset(preset))
                        Text(preset.title)
                    }
                    .tag(preset)
                }
            }
            Stepper(value: warningThreshold, in: 5...95, step: 5) {
                LabeledContent("Warning at", value: "\(Int(settings.warningThreshold))%")
            }
            Stepper(value: criticalThreshold, in: 10...100, step: 5) {
                LabeledContent("Critical at", value: "\(Int(settings.criticalThreshold))%")
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Thresholds color percentages when “Color by” is Usage threshold, or when a window has no reset time.")
                .foregroundStyle(.secondary)
        }
    }

    private var warningThreshold: Binding<Double> {
        Binding {
            settings.warningThreshold
        } set: { newValue in
            settings.warningThreshold = newValue
            if settings.criticalThreshold <= newValue { settings.criticalThreshold = min(newValue + 5, 100) }
        }
    }

    private var criticalThreshold: Binding<Double> {
        Binding {
            settings.criticalThreshold
        } set: { newValue in
            settings.criticalThreshold = newValue
            if settings.warningThreshold >= newValue { settings.warningThreshold = max(newValue - 5, 5) }
        }
    }

    // MARK: General

    private var generalSection: some View {
        Section("General") {
            Stepper(value: $settings.refreshInterval, in: SettingsStore.refreshRange, step: 30) {
                LabeledContent("Refresh every", value: Format.interval(settings.refreshInterval))
            }
            Toggle("Launch at login", isOn: launchBinding)
            if launchStatus == .requiresApproval {
                Text("Approve PaceBar in System Settings › General › Login Items.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let launchError {
                Text(launchError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding {
            launchAtLogin
        } set: { on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                launchError = nil
            } catch {
                launchError = "Couldn't change the login item: \(error.localizedDescription)"
            }
            launchStatus = SMAppService.mainApp.status
            launchAtLogin = launchStatus == .enabled || launchStatus == .requiresApproval
        }
    }

    // MARK: Diagnostics

    private var diagnosticsSection: some View {
        Section {
            HStack {
                Button("Copy diagnostic") {
                    let text = store.diagnosticReport().text
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                if copied {
                    Text("Copied")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Copies app and macOS versions, Keychain item count, token expiry (relative), the last HTTP status and error, and the response's key names and value types. Never the token, account names or usage values.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Weekday toggles in the user's locale order. Values are Gregorian weekday numbers (1 = Sunday).
private struct DayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 4) {
            ForEach(order, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

private struct ThemeSwatch: View {
    let theme: Theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach([theme.chill, theme.onTrack, theme.warning, theme.hot], id: \.hex) { c in
                Circle().fill(c.color).frame(width: 7, height: 7)
            }
        }
    }
}
