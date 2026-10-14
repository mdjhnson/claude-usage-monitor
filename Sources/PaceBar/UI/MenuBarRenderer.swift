import AppKit

/// Draws the status item as a non-template image, like TokenEater's `MenuBarRenderer`.
///
/// The image draws lazily: AppKit calls the drawing handler under the menu bar's current
/// appearance, so dynamic colors such as the label color re-resolve whenever macOS flips the
/// menu bar between light and dark text (for example when the wallpaper changes).
enum MenuBarRenderer {
    struct Segment: Sendable {
        let label: String
        let value: String
        let color: NSColor
        var accessory: Accessory? = nil
    }

    /// Drawn after the value: a reset countdown, or a symbol for the pacing zone.
    enum Accessory: Sendable {
        case text(String)
        case symbol(name: String, color: NSColor)
    }

    static let height: CGFloat = 22
    static let segmentSpacing: CGFloat = 6
    static let edgePadding: CGFloat = 1

    static func image(segments: [Segment], style: MenuBarStyle, dimmed: Bool) -> NSImage {
        let widths = segments.map { layout($0, style: style, dimmed: dimmed).width }
        let width = widths.reduce(edgePadding * 2, +) + segmentSpacing * CGFloat(max(widths.count - 1, 0))
        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x = edgePadding
            for segment in segments {
                let piece = layout(segment, style: style, dimmed: dimmed)
                piece.draw(NSRect(x: x, y: 0, width: piece.width, height: height))
                x += piece.width + segmentSpacing
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private struct Piece {
        let width: CGFloat
        let draw: (NSRect) -> Void
    }

    private static func layout(_ segment: Segment, style: MenuBarStyle, dimmed: Bool) -> Piece {
        let tint = dimmed ? segment.color.withAlphaComponent(0.5) : segment.color
        switch style {
        case .classic:
            let labelFont = NSFont.systemFont(ofSize: 9, weight: .medium)
            let text = NSMutableAttributedString(string: segment.label + " ", attributes: [
                .font: labelFont,
                .foregroundColor: NSColor.labelColor,
            ])
            text.append(NSAttributedString(string: segment.value, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: tint,
            ]))
            if case .text(let detail) = segment.accessory {
                text.append(NSAttributedString(string: " " + detail, attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: NSColor.labelColor,
                ]))
            }
            let size = text.size()
            let symbol = symbolImage(segment.accessory, pointSize: 9, dimmed: dimmed)
            let symbolWidth = symbol.map { symbolGap + $0.size.width } ?? 0
            return Piece(width: ceil(size.width + symbolWidth)) { rect in
                text.draw(at: NSPoint(x: rect.minX, y: rect.midY - size.height / 2))
                if let symbol {
                    symbol.draw(at: NSPoint(x: rect.minX + size.width + symbolGap, y: rect.midY - symbol.size.height / 2),
                                from: .zero, operation: .sourceOver, fraction: 1)
                }
            }

        case .pill:
            var string = "\(segment.label) \(segment.value)"
            if case .text(let detail) = segment.accessory { string += " · " + detail }
            let text = NSAttributedString(string: string, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                .foregroundColor: tint,
            ])
            let textSize = text.size()
            let symbol = symbolImage(segment.accessory, pointSize: 10, dimmed: dimmed)
            let symbolWidth = symbol.map { symbolGap + $0.size.width } ?? 0
            let pillHeight: CGFloat = 17
            let width = ceil(textSize.width + symbolWidth) + 14
            return Piece(width: width) { rect in
                let pillRect = NSRect(x: rect.minX + 0.4, y: rect.midY - pillHeight / 2, width: width - 0.8, height: pillHeight)
                let path = NSBezierPath(roundedRect: pillRect, xRadius: 8.5, yRadius: 8.5)
                tint.withAlphaComponent(0.18 * tint.alphaComponent).setFill()
                path.fill()
                tint.withAlphaComponent(0.55 * tint.alphaComponent).setStroke()
                path.lineWidth = 0.8
                path.stroke()
                text.draw(at: NSPoint(x: rect.minX + 7, y: rect.midY - textSize.height / 2))
                if let symbol {
                    symbol.draw(at: NSPoint(x: rect.minX + 7 + textSize.width + symbolGap, y: rect.midY - symbol.size.height / 2),
                                from: .zero, operation: .sourceOver, fraction: 1)
                }
            }
        }
    }

    static let symbolGap: CGFloat = 3

    /// The accessory's SF Symbol in its own color. Called inside the drawing handler, so a
    /// dynamic color such as the label color resolves for the menu bar's current appearance.
    private static func symbolImage(_ accessory: Accessory?, pointSize: CGFloat, dimmed: Bool) -> NSImage? {
        guard case .symbol(let name, let color) = accessory else { return nil }
        let tint = dimmed ? color.withAlphaComponent(0.5) : color
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }
}
