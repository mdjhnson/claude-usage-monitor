import Foundation

/// sRGB colors as `0xRRGGBB`, for themes people define themselves.
public enum HexColor {
    /// Parses "#RRGGBB" or "#RGB", with or without "#", in any case. Surrounding spaces are ignored.
    public static func parse(_ text: String) -> UInt32? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 3 || digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        return UInt32(digits, radix: 16)
    }

    /// "#0A84FF".
    public static func format(_ hex: UInt32) -> String {
        "#" + String(format: "%06X", hex & 0xFFFFFF)
    }

    /// WCAG 2 contrast ratio between two colors, from 1 (identical) to 21 (black on white).
    public static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// WCAG 2 relative luminance.
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}
