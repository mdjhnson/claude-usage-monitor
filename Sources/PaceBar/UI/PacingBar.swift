import SwiftUI
import PaceBarCore

/// TokenEater's non-compact pacing bar: rounded track, zone gradient fill to actual usage,
/// a pulsing white knob at actual usage, and a triangle at the expected pace.
struct PacingBar: View {
    let actual: Double
    /// 0...1. Expected pace, or calendar "now" when the workweek schedule is active.
    let markerFraction: Double
    let zoneColor: ThemeColor
    let offTimeRanges: [ClosedRange<Double>]
    let isOffTime: Bool

    @State private var animatedActual: Double = 0
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trackHeight: CGFloat = 8
    private let knobSize: CGFloat = 10
    private let markerSize: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fillWidth = width * CGFloat(min(max(animatedActual, 0), 100) / 100)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: trackHeight)

                if !offTimeRanges.isEmpty {
                    OffTimeHatch(ranges: offTimeRanges)
                        .frame(height: trackHeight)
                        .clipShape(Capsule())
                }

                Capsule()
                    .fill(LinearGradient(colors: [zoneColor.color, zoneColor.lighter()], startPoint: .leading, endPoint: .trailing))
                    .frame(width: fillWidth, height: trackHeight)

                Triangle()
                    .fill(Color.white.opacity(isOffTime ? 0.25 : 0.5))
                    .frame(width: markerSize, height: markerSize)
                    .offset(x: width * CGFloat(min(max(markerFraction, 0), 1)) - markerSize / 2)

                Circle()
                    .fill(isOffTime ? Color.white.opacity(0.45) : Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .white.opacity(isOffTime ? 0.2 : 0.5), radius: pulsing ? 6 : 2)
                    .offset(x: fillWidth - knobSize / 2)
            }
            .frame(width: width, height: geo.size.height)
        }
        .frame(height: 20)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { animatedActual = actual }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulsing = true }
            }
        }
        .onChange(of: actual) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { animatedActual = newValue }
        }
        .accessibilityHidden(true)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// Diagonal hatching over off-time ranges (TokenEater's `OffDayHatch`).
private struct OffTimeHatch: View {
    let ranges: [ClosedRange<Double>]

    var body: some View {
        Canvas { context, size in
            for range in ranges {
                let rect = CGRect(x: size.width * range.lowerBound, y: 0,
                                  width: size.width * (range.upperBound - range.lowerBound), height: size.height)
                guard rect.width > 0 else { continue }
                context.fill(Path(rect), with: .color(.white.opacity(0.04)))
                var lines = Path()
                var x = rect.minX - size.height
                while x < rect.maxX {
                    lines.move(to: CGPoint(x: x, y: size.height))
                    lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 4
                }
                var clipped = context
                clipped.clip(to: Path(rect))
                clipped.stroke(lines, with: .color(.white.opacity(0.11)), lineWidth: 0.75)
            }
        }
    }
}
