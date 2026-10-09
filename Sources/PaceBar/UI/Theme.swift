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

    /// TokenEater's `lighter()`: saturation down 0.3 × amount, brightness up by amount.
    func lighter(by amount: CGFloat = 0.15) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: max(s - amount * 0.3, 0), brightness: min(b + amount, 1))
    }
}

enum ThemePreset: String, CaseIterable, Identifiable {
    case `default`, monochrome, neon, pastel
    var id: String { rawValue }
    var title: String { rawValue == "default" ? "Default" : rawValue.capitalized }
}

/// Theme tokens. Hex values are TokenEater's presets (`Shared/Models/ThemeModels.swift`).
struct Theme: Equatable {
    let gaugeNormal, gaugeWarning, gaugeCritical: ThemeColor
    let chill, onTrack, warning, hot: ThemeColor
    let background, text: ThemeColor

    /// TokenEater's popover surface, rgb(0.08, 0.08, 0.09).
    static let popoverSurface = ThemeColor(hex: 0x141417)

    static func preset(_ preset: ThemePreset) -> Theme {
        switch preset {
        case .default:
            Theme(gaugeNormal: .init(hex: 0x22C55E), gaugeWarning: .init(hex: 0xF97316), gaugeCritical: .init(hex: 0xEF4444),
                  chill: .init(hex: 0x32D74B), onTrack: .init(hex: 0x0A84FF), warning: .init(hex: 0xFF9500), hot: .init(hex: 0xFF453A),
                  background: .init(hex: 0x000000), text: .init(hex: 0xFFFFFF))
        case .monochrome:
            Theme(gaugeNormal: .init(hex: 0x8E8E93), gaugeWarning: .init(hex: 0xC7C7CC), gaugeCritical: .init(hex: 0xFFFFFF),
                  chill: .init(hex: 0x8E8E93), onTrack: .init(hex: 0xAEAEB2), warning: .init(hex: 0xD6D6D6), hot: .init(hex: 0xFFFFFF),
                  background: .init(hex: 0x000000), text: .init(hex: 0xFFFFFF))
        case .neon:
            Theme(gaugeNormal: .init(hex: 0x00FF87), gaugeWarning: .init(hex: 0xFFD000), gaugeCritical: .init(hex: 0xFF006E),
                  chill: .init(hex: 0x00FF87), onTrack: .init(hex: 0x00D4FF), warning: .init(hex: 0xFFD000), hot: .init(hex: 0xFF006E),
                  background: .init(hex: 0x0A0A0A), text: .init(hex: 0xFFFFFF))
        case .pastel:
            Theme(gaugeNormal: .init(hex: 0x86EFAC), gaugeWarning: .init(hex: 0xFDE68A), gaugeCritical: .init(hex: 0xFCA5A5),
                  chill: .init(hex: 0x86EFAC), onTrack: .init(hex: 0x93C5FD), warning: .init(hex: 0xFDE68A), hot: .init(hex: 0xFCA5A5),
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

    /// Default keeps TokenEater's surface exactly; other presets blend their background in by half.
    var popoverBackground: Color {
        guard background != Theme.preset(.default).background else { return Self.popoverSurface.color }
        let a = Self.popoverSurface.nsColor, b = background.nsColor
        return Color(nsColor: a.blended(withFraction: 0.5, of: b) ?? a)
    }

    var textColor: Color { text.color }
}
