import AppKit
import ServiceManagement
import SwiftUI
import PaceBarCore

/// A preferences window with toolbar tabs, one short SwiftUI form per tab.
/// The window resizes to fit whichever tab is selected.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(store: UsageStore, settings: SettingsStore, notifier: Notifier) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for pane in SettingsView.Pane.allCases {
            let hosting = NSHostingController(rootView: SettingsView(pane: pane, store: store, settings: settings, notifier: notifier))
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
        case pacing, menuBar, appearance, notifications, general, about

        var title: String {
            switch self {
            case .pacing: "Pacing"
            case .menuBar: "Menu Bar"
            case .appearance: "Appearance"
            case .notifications: "Notifications"
            case .general: "General"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .pacing: "gauge.with.needle"
            case .menuBar: "menubar.rectangle"
            case .appearance: "paintpalette"
            case .notifications: "bell"
            case .general: "gearshape"
            case .about: "info.circle"
            }
        }
    }

    let pane: Pane
    let store: UsageStore
    @Bindable var settings: SettingsStore
    let notifier: Notifier

    @State private var launchAtLogin = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
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
                if settings.themePreset == .custom {
                    customColorsSection
                }
            case .notifications:
                notificationsSection
            case .general:
                generalSection
                diagnosticsSection
            case .about:
                AboutPane()
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
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
        Section {
            Picker("Style", selection: $settings.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Color by", selection: $settings.colorMode) {
                ForEach(ColorMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("After each value", selection: $settings.menuBarExtra) {
                ForEach(MenuBarExtra.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Monochrome menu bar", isOn: $settings.monochromeMenuBar)
        } header: {
            Text("Menu bar")
        } footer: {
            Text(menuBarExtraFooter)
                .foregroundStyle(.secondary)
        }
    }

    private var menuBarExtraFooter: String {
        switch settings.menuBarExtra {
        case .none: "Add a reset countdown or a pace symbol after each percentage."
        case .countdown: "Time until each limit resets, like 1h25m or 3d 4h."
        case .arrows: "Down when you're under pace and can ramp up. Up when you're ahead of pace (two when Hot) and should back off. Nothing when on track."
        case .fireAndIce: "Ice when you're running cold and can ramp up. A flame when you're running hot (filled when Hot) and should back off. Nothing when on track."
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
            Toggle("Usage graph on each card", isOn: $settings.showUsageGraph)
            Picker("Theme", selection: themeSelection) {
                ForEach(ThemePreset.allCases) { preset in
                    HStack(spacing: 6) {
                        ThemeSwatch(theme: preset == .custom ? .custom(settings.customColors) : .preset(preset))
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
            Text("The usage graph plots this cycle's readings against the steady pace. It starts when PaceBar launches; before the first reading the line from the window's start is dashed. Thresholds color percentages when “Color by” is Usage threshold, or when a window has no reset time.")
                .foregroundStyle(.secondary)
        }
    }

    /// A first switch to Custom copies the theme that was showing, so editing starts from it.
    private var themeSelection: Binding<ThemePreset> {
        Binding { settings.themePreset } set: { settings.selectTheme($0) }
    }

    // MARK: Custom colors

    private var customColorsSection: some View {
        Section {
            LabeledContent("Start from") {
                Menu("Preset") {
                    ForEach(ThemePreset.builtIn) { preset in
                        Button(preset.title) { settings.resetCustomColors(to: preset) }
                    }
                }
                .fixedSize()
            }
            // Two columns keep all nine colors on screen: zones beside thresholds, popover below.
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    groupTitle("Pacing zones").gridCellColumns(2)
                    groupTitle("Usage thresholds").gridCellColumns(2)
                }
                ForEach(Theme.Token.zones.indices, id: \.self) { i in
                    GridRow {
                        colorCells(Theme.Token.zones[i])
                        if i < Theme.Token.thresholds.count {
                            colorCells(Theme.Token.thresholds[i])
                        }
                    }
                }
                GridRow {
                    groupTitle("Popover").gridCellColumns(4)
                }
                .padding(.top, 4)
                GridRow {
                    ForEach(Theme.Token.popover) { colorCells($0) }
                }
            }
            .padding(.vertical, 2)
            let contrast = settings.theme.textContrast
            if contrast < Self.minimumContrast {
                Label("Text may be hard to read on this background (contrast \(String(format: "%.1f", contrast)):1; aim for 4.5:1 or more).",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Custom colors")
        } footer: {
            Text("Type a hex code (#0A84FF or #08F) or click a swatch to pick a color. “Start from” replaces every custom color with a preset's. The popover is designed for dark backgrounds: its cards and dividers are light overlays that fade on a light background.")
                .foregroundStyle(.secondary)
        }
    }

    /// WCAG AA for normal text.
    static let minimumContrast = 4.5

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// Two grid cells: the color's name, then its hex field and swatch.
    @ViewBuilder
    private func colorCells(_ token: Theme.Token) -> some View {
        Text(token.title)
        HexColorField(title: token.title, color: Binding {
            settings.theme[token]
        } set: { newValue in
            settings.customColors[token] = newValue
        })
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

    // MARK: Notifications

    private var notificationsSection: some View {
        Section {
            Toggle("Usage alerts", isOn: notificationBinding(\.notifyUsage))
            Toggle("Running hot and back on pace", isOn: notificationBinding(\.notifyPace))
            Picker("Before the session resets", selection: notificationBinding(\.sessionReminderMinutes)) {
                ForEach(SettingsStore.sessionReminderChoices, id: \.self) { Text(reminderTitle($0)).tag($0) }
            }
            Picker("Before the weekly reset", selection: notificationBinding(\.weeklyReminderMinutes)) {
                ForEach(SettingsStore.weeklyReminderChoices, id: \.self) { Text(reminderTitle($0)).tag($0) }
            }
            if notifier.isDenied && settings.anyNotificationsOn {
                Text("Notifications are turned off for PaceBar. Turn them on in System Settings › Notifications › PaceBar.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Usage alerts fire once per reset cycle at your warning (\(Int(settings.warningThreshold))%) and critical (\(Int(settings.criticalThreshold))%) thresholds, set under Appearance. Running hot fires when a limit enters the Hot zone, and again when it's back on pace. Only limits shown in the popover notify.")
                .foregroundStyle(.secondary)
        }
        .task { await notifier.refreshAuthorization() }
    }

    /// Turning any notification on asks macOS for permission the first time.
    private func notificationBinding<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>) -> Binding<Value> {
        Binding {
            settings[keyPath: keyPath]
        } set: { newValue in
            settings[keyPath: keyPath] = newValue
            if settings.anyNotificationsOn { notifier.requestAuthorization() }
        }
    }

    private func reminderTitle(_ minutes: Int) -> String {
        minutes == 0 ? "Off" : Notifier.lead(TimeInterval(minutes * 60)) + " before"
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
                    Task {
                        let text = await store.diagnosticReport().text
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                    }
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
            // By position: a custom theme may repeat a color.
            ForEach(Array(Theme.Token.zones.enumerated()), id: \.offset) { _, token in
                Circle().fill(theme[token].color).frame(width: 7, height: 7)
            }
        }
    }
}

/// One custom color: a hex field and the system color picker, kept in step both ways.
private struct HexColorField: View {
    let title: String
    @Binding var color: ThemeColor

    @State private var text = ""
    @FocusState private var focused: Bool

    private var isValid: Bool { HexColor.parse(text) != nil }

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $text, prompt: Text("#RRGGBB"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 76)
                .focused($focused)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red, lineWidth: isValid ? 0 : 1.5))
                .accessibilityLabel("\(title) hex code")
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onChange(of: text) { _, newValue in
                    // Apply a full six-digit code as it's typed, so the preview follows along.
                    // Three-digit codes wait for Return, since they're a prefix of six-digit ones.
                    let digits = newValue.trimmingCharacters(in: .whitespaces).trimmingPrefix("#")
                    if digits.count == 6, let hex = HexColor.parse(newValue), hex != color.hex {
                        color = ThemeColor(hex: hex)
                    }
                }
            ColorPicker(title, selection: Binding { color.color } set: { color = ThemeColor($0) }, supportsOpacity: false)
                .labelsHidden()
                .controlSize(.small)
        }
        .onAppear { text = color.hexString }
        .onChange(of: color) { _, newValue in
            // Leave the field alone while it's being typed into and already says this color.
            if !(focused && HexColor.parse(text) == newValue.hex) { text = newValue.hexString }
        }
    }

    /// Return or leaving the field: apply a valid code in canonical form, or put back the current one.
    private func commit() {
        if let hex = HexColor.parse(text) { color = ThemeColor(hex: hex) }
        text = color.hexString
    }
}
