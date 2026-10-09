import AppKit

/// Draws the status item as a non-template image, like TokenEater's `MenuBarRenderer`.
@MainActor
enum MenuBarRenderer {
    struct Segment {
        let label: String
        let value: String
        let color: NSColor
    }

    static let height: CGFloat = 22
    static let segmentSpacing: CGFloat = 6
    static let edgePadding: CGFloat = 1

    /// - Parameter appearance: the status button's effective appearance, so dynamic label
    ///   colors resolve for a light or dark menu bar.
    static func image(segments: [Segment], style: MenuBarStyle, dimmed: Bool, appearance: NSAppearance, scale: CGFloat) -> NSImage {
        let pieces = segments.map { piece(for: $0, style: style, dimmed: dimmed) }
        let width = pieces.reduce(edgePadding * 2) { $0 + $1.width } + segmentSpacing * CGFloat(max(pieces.count - 1, 0))
        let size = NSSize(width: ceil(width), height: height)

        let image = NSImage(size: size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return image }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            var x = edgePadding
            for piece in pieces {
                piece.draw(NSRect(x: x, y: 0, width: piece.width, height: height))
                x += piece.width + segmentSpacing
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    private struct Piece {
        let width: CGFloat
        let draw: (NSRect) -> Void
    }

    private static func piece(for segment: Segment, style: MenuBarStyle, dimmed: Bool) -> Piece {
        let tint = dimmed ? segment.color.withAlphaComponent(0.5) : segment.color
        switch style {
        case .classic:
            let text = NSMutableAttributedString(string: segment.label + " ", attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            text.append(NSAttributedString(string: segment.value, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: tint,
            ]))
            let size = text.size()
            return Piece(width: ceil(size.width)) { rect in
                text.draw(at: NSPoint(x: rect.minX, y: rect.midY - size.height / 2))
            }

        case .pill:
            let text = NSAttributedString(string: "\(segment.label) \(segment.value)", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: tint,
            ])
            let textSize = text.size()
            let pillHeight: CGFloat = 17
            let width = ceil(textSize.width) + 14
            return Piece(width: width) { rect in
                let pillRect = NSRect(x: rect.minX + 0.4, y: rect.midY - pillHeight / 2, width: width - 0.8, height: pillHeight)
                let path = NSBezierPath(roundedRect: pillRect, xRadius: 8.5, yRadius: 8.5)
                tint.withAlphaComponent(0.18 * tint.alphaComponent).setFill()
                path.fill()
                tint.withAlphaComponent(0.55 * tint.alphaComponent).setStroke()
                path.lineWidth = 0.8
                path.stroke()
                text.draw(at: NSPoint(x: rect.minX + 7, y: rect.midY - textSize.height / 2))
            }
        }
    }
}
