import SwiftUI
import PaceBarCore

/// This cycle's usage plotted against the steady pace, so an uneven ramp shows its real shape
/// instead of a single point on the bar.
///
/// - Dashed white: the pace line (flat through off time in workweek mode).
/// - Zone color: readings since launch. The window starts at 0%, so the line from the window's
///   start to the first reading is drawn dashed, since nothing was measured in between.
/// - White dot: the latest reading.
struct UsageGraph: View {
    let samples: [UsageSample]
    let pace: [GraphPoint]
    let resetsAt: Date
    let kind: WindowKind
    /// The latest utilization, used when no reading has been recorded yet.
    let current: Double
    let color: ThemeColor
    let textColor: Color
    let now: Date

    static let height: CGFloat = 44

    private var start: Date { resetsAt.addingTimeInterval(-kind.duration) }

    /// Readings inside this window, falling back to the current value at `now`.
    private var readings: [GraphPoint] {
        let duration = kind.duration
        let points = samples
            .filter { $0.date >= start && $0.date <= resetsAt }
            .map { GraphPoint(x: $0.date.timeIntervalSince(start) / duration, y: $0.utilization) }
        if !points.isEmpty { return points }
        return [GraphPoint(x: min(max(now.timeIntervalSince(start) / duration, 0), 1), y: current)]
    }

    var body: some View {
        let readings = readings
        let yMax = max(100, readings.map(\.y).max() ?? 0)

        VStack(spacing: 2) {
            Canvas { context, size in
                func point(_ p: GraphPoint) -> CGPoint {
                    CGPoint(x: size.width * min(max(p.x, 0), 1),
                            y: size.height * (1 - min(max(p.y, 0), yMax) / yMax))
                }
                let origin = point(GraphPoint(x: 0, y: 0))
                let measured = readings.map(point)
                guard let first = measured.first, let last = measured.last else { return }

                // Baseline.
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height - 0.25))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.25))
                context.stroke(baseline, with: .color(.white.opacity(0.06)), lineWidth: 0.5)

                // Area under the whole line, origin through the latest reading.
                var area = Path()
                area.move(to: CGPoint(x: origin.x, y: size.height))
                area.addLine(to: origin)
                measured.forEach { area.addLine(to: $0) }
                area.addLine(to: CGPoint(x: last.x, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [color.color.opacity(0.28), color.color.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)
                ))

                // Pace line.
                var paceLine = Path()
                paceLine.addLines(pace.map(point))
                context.stroke(paceLine, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // Unmeasured stretch from the window's start to the first reading.
                var inferred = Path()
                inferred.move(to: origin)
                inferred.addLine(to: first)
                context.stroke(inferred, with: .color(color.color.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [2, 3]))

                // Measured readings.
                if measured.count > 1 {
                    var line = Path()
                    line.addLines(measured)
                    context.stroke(line, with: .color(color.color),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }

                let dot = CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: dot), with: .color(.white))
            }
            .frame(height: Self.height)

            HStack {
                Text(label(start))
                Spacer()
                Text(label(resetsAt))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(textColor.opacity(0.3))
        }
        .accessibilityHidden(true)
    }

    /// Session ends show the time; weekly ends add the weekday ("Sat 4 AM").
    private func label(_ date: Date) -> String {
        kind == .session ? Format.time(date) : date.formatted(.dateTime.weekday(.abbreviated).hour())
    }
}
