// Draws PaceBar's app icon (a small pacing bar on a dark tile) into an .iconset folder.
// Run by build.sh; generating at build time keeps binary assets out of the repo.
//   swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let s = CGFloat(pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Tile: macOS icon grid inset (~10%), continuous-ish corners.
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: srgb(0x26262C), ending: srgb(0x141417))!.draw(in: tilePath, angle: -90)
    srgb(0xFFFFFF, 0.08).setStroke()
    tilePath.lineWidth = max(1, s * 0.004)
    tilePath.stroke()

    // Pacing bar: track, chill→on-track gradient fill to 62%, white knob, pace triangle at 50%.
    let barHeight = s * 0.075
    let bar = NSRect(x: tile.minX + s * 0.12, y: tile.midY - barHeight / 2, width: tile.width - s * 0.24, height: barHeight)
    srgb(0xFFFFFF, 0.1).setFill()
    NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    let fill = NSRect(x: bar.minX, y: bar.minY, width: bar.width * 0.62, height: barHeight)
    NSGradient(starting: srgb(0x32D74B), ending: srgb(0x0A84FF))!
        .draw(in: NSBezierPath(roundedRect: fill, xRadius: barHeight / 2, yRadius: barHeight / 2), angle: 0)

    let marker = s * 0.075
    let mx = bar.minX + bar.width * 0.5
    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: mx, y: bar.minY - s * 0.02))
    triangle.line(to: NSPoint(x: mx + marker / 2, y: bar.minY - s * 0.02 - marker))
    triangle.line(to: NSPoint(x: mx - marker / 2, y: bar.minY - s * 0.02 - marker))
    triangle.close()
    srgb(0xFFFFFF, 0.55).setFill()
    triangle.fill()

    let knob = s * 0.12
    let shadow = NSShadow()
    shadow.shadowColor = srgb(0xFFFFFF, 0.5)
    shadow.shadowBlurRadius = s * 0.03
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: fill.maxX - knob / 2, y: bar.midY - knob / 2, width: knob, height: knob)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try drawIcon(pixels: points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
