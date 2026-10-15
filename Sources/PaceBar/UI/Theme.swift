import AppKit
import SwiftUI
import PaceBarCore

/// An sRGB color from a hex literal, usable from both AppKit and SwiftUI.
struct ThemeColor: Equatable {
    let hex: UInt32

    private var components: (r: CGFloat, g: CGFloat, b: CGFloat) {
        (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }

    var nsColor: NSColor {
        let c = components
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    var color: Color { Color(nsColor: nsColor) }

    /// "#0A84FF".
    var hexString: String { HexColor.format(hex) }

    /// The nearest sRGB color, for values coming from the system color picker (which may be P3).
    init(nsColor: NSColor) {
        let srgb = nsColor.usingColorSpace(.sRGB) ?? .black
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        hex = byte(srgb.redComponent) << 16 | byte(srgb.greenComponent) << 8 | byte(srgb.blueComponent)
    }

    init(_ color: Color) {
        self.init(nsColor: NSColor(color))
    }

    init(hex: UInt32) {
        self.hex = hex & 0xFFFFFF
    }

    /// TokenEater's `lighter()`: saturation down 0.3 × amount, brightness up by amount.
    func lighter(by amount: CGFloat = 0.15) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: max(s - amount * 0.3, 0), brightness: min(b + amount, 1))
    }
}

enum ThemePreset: String, CaseIterable, Identifiable {
    case `default`, monochrome, neon, pastel, custom
    var id: String { rawValue }
    var title: String { rawValue == "default" ? "Default" : rawValue.capitalized }

    /// The presets a custom theme can start from.
    static let builtIn: [ThemePreset] = [.default, .monochrome, .neon, .pastel]
}

/// Theme tokens. Hex values are TokenEater's presets (`Shared/Models/ThemeModels.swift`).
struct Theme: Equatable {
    let gaugeNormal, gaugeWarning, gaugeCritical: ThemeColor
    let chill, onTrack, warning, hot: ThemeColor
    let background, text: ThemeColor
    /// A custom background is used exactly as chosen; preset backgrounds are blended (see `popoverBackground`).
    var isCustom = false

    /// Each color a custom theme can set, in the order Settings lists them.
    enum Token: String, CaseIterable, Identifiable {
        case chill, onTrack, warning, hot, gaugeNormal, gaugeWarning, gaugeCritical, background, text
        var id: String { rawValue }

        var title: String {
            switch self {
            case .chill: "Chill"
            case .onTrack: "On track"
            case .warning: "Watch out"
            case .hot: "Hot"
            case .gaugeNormal: "Normal"
            case .gaugeWarning: "Warning"
            case .gaugeCritical: "Critical"
            case .background: "Background"
            case .text: "Text"
            }
        }

        static let zones: [Token] = [.chill, .onTrack, .warning, .hot]
        static let thresholds: [Token] = [.gaugeNormal, .gaugeWarning, .gaugeCritical]
        static let popover: [Token] = [.background, .text]
    }

    subscript(token: Token) -> ThemeColor {
        switch token {
        case .chill: chill
        case .onTrack: onTrack
        case .warning: warning
        case .hot: hot
        case .gaugeNormal: gaugeNormal
        case .gaugeWarning: gaugeWarning
        case .gaugeCritical: gaugeCritical
        case .background: background
        case .text: text
        }
    }

    /// A custom theme. Tokens it doesn't set come from `base`.
    static func custom(_ colors: [Token: ThemeColor], base: Theme = .preset(.default)) -> Theme {
        func pick(_ token: Token) -> ThemeColor { colors[token] ?? base[token] }
        return Theme(
            gaugeNormal: pick(.gaugeNormal), gaugeWarning: pick(.gaugeWarning), gaugeCritical: pick(.gaugeCritical),
            chill: pick(.chill), onTrack: pick(.onTrack), warning: pick(.warning), hot: pick(.hot),
            background: pick(.background), text: pick(.text), isCustom: true
        )
    }

    /// Every token's color, for seeding a custom theme from this one.
    var colors: [Token: ThemeColor] {
        Dictionary(uniqueKeysWithValues: Token.allCases.map { ($0, self[$0]) })
    }

    /// TokenEater's popover surface, rgb(0.08, 0.08, 0.09).
    static let popoverSurface = ThemeColor(hex: 0x141417)

    /// A built-in preset. `.custom` needs the person's colors, so it lives on `SettingsStore.theme`;
    /// here it falls back to Default, which is also where a new custom theme starts.
    static func preset(_ preset: ThemePreset) -> Theme {
        switch preset {
        case .default, .custom:
            Theme(gaugeNormal: .init(hex: 0x22C55E), gaugeWarning: .init(hex: 0xF97316), gaugeCritical: .init(hex: 0xEF4444),
                  chill: .init(hex: 0x0A84FF), onTrack: .init(hex: 0x32D74B), warning: .init(hex: 0xFF9500), hot: .init(hex: 0xFF453A),
                  background: .init(hex: 0x000000), text: .init(hex: 0xFFFFFF))
        case .monochrome:
            Theme(gaugeNormal: .init(hex: 0x8E8E93), gaugeWarning: .init(hex: 0xC7C7CC), gaugeCritical: .init(hex: 0xFFFFFF),
                  chill: .init(hex: 0x8E8E93), onTrack: .init(hex: 0xAEAEB2), warning: .init(hex: 0xD6D6D6), hot: .init(hex: 0xFFFFFF),
                  background: .init(hex: 0x000000), text: .init(hex: 0xFFFFFF))
        case .neon:
            Theme(gaugeNormal: .init(hex: 0x00FF87), gaugeWarning: .init(hex: 0xFFD000), gaugeCritical: .init(hex: 0xFF006E),
                  chill: .init(hex: 0x00D4FF), onTrack: .init(hex: 0x00FF87), warning: .init(hex: 0xFFD000), hot: .init(hex: 0xFF006E),
                  background: .init(hex: 0x0A0A0A), text: .init(hex: 0xFFFFFF))
        case .pastel:
            Theme(gaugeNormal: .init(hex: 0x86EFAC), gaugeWarning: .init(hex: 0xFDE68A), gaugeCritical: .init(hex: 0xFCA5A5),
                  chill: .init(hex: 0x93C5FD), onTrack: .init(hex: 0x86EFAC), warning: .init(hex: 0xFDE68A), hot: .init(hex: 0xFCA5A5),
                  background: .init(hex: 0x1A1A2E), text: .init(hex: 0xE2E8F0))
        }
    }

    func zone(_ zone: PacingZone) -> ThemeColor {
        switch zone {
        case .chill: chill
        case .onTrack: onTrack
        case .warning: warning
        case .hot: hot
        }
    }

    func usage(_ utilization: Double, warningAt: Double, criticalAt: Double) -> ThemeColor {
        if utilization >= criticalAt { return gaugeCritical }
        if utilization >= warningAt { return gaugeWarning }
        return gaugeNormal
    }

    /// The percentage color: pacing zone when available and chosen, otherwise usage thresholds.
    func tint(utilization: Double, pacing: PacingResult?, mode: ColorMode, warningAt: Double, criticalAt: Double) -> ThemeColor {
        if mode == .pacing, let pacing { return zone(pacing.zone) }
        return usage(utilization, warningAt: warningAt, criticalAt: criticalAt)
    }

    /// The popover's actual background color.
    /// Default keeps TokenEater's surface exactly; other presets blend their background in by half;
    /// a custom theme uses its background as chosen.
    var popoverBackgroundColor: ThemeColor {
        if isCustom { return background }
        guard background != Theme.preset(.default).background else { return Self.popoverSurface }
        let a = Self.popoverSurface.nsColor, b = background.nsColor
        return ThemeColor(nsColor: a.blended(withFraction: 0.5, of: b) ?? a)
    }

    var popoverBackground: Color { popoverBackgroundColor.color }

    /// Every token as `0xRRGGBB` for the widget, with `background` already resolved to the
    /// popover's actual background.
    var widgetColors: [String: UInt32] {
        var colors = Dictionary(uniqueKeysWithValues: Token.allCases.map { ($0.rawValue, self[$0].hex) })
        colors[Token.background.rawValue] = popoverBackgroundColor.hex
        return colors
    }

    /// The theme the app handed the widget. It's custom, so the resolved background is used as is.
    static func widget(_ colors: [String: UInt32]) -> Theme {
        .custom(colors.reduce(into: [:]) { result, entry in
            if let token = Token(rawValue: entry.key) { result[token] = ThemeColor(hex: entry.value) }
        })
    }

    /// WCAG contrast between the text and the popover background.
    var textContrast: Double { HexColor.contrastRatio(text.hex, popoverBackgroundColor.hex) }

    var textColor: Color { text.color }
}
