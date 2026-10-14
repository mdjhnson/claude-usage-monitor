import SwiftUI
import PaceBarCore

/// This cycle's usage plotted against the steady pace, so an uneven ramp shows its real shape
/// instead of a single point on the bar.
///
/// - Dashed white: the pace line (flat through off time in workweek mode).
/// - Zone color: readings since launch. The window starts at 0%, so the line from the window's
///   start to the first reading is drawn dashed, since nothing was measured in between.
/// - White dot: the latest reading.
/// - Weekly graphs can split into days: faint lines at local midnights, optionally with day
///   names underneath (today's brighter).
/// - Hover: snaps to the nearest reading and shows its time, usage and the pace at that moment
///   in the axis row, so the label never covers the line.
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
    var dayMarkers: WeeklyDayMarkers = .off
    /// The plot's height. Nil fills whatever height the parent offers (the large widget).
    var height: CGFloat? = Self.height
    /// The shortest a flexible plot gets.
    static let minFlexibleHeight: CGFloat = 28

    static let height: CGFloat = 44
    static let dayNameHeight: CGFloat = 10
    /// A partial day narrower than this gets a line but no name.
    static let minDayNameWidth: CGFloat = 22

    /// Pointer position across the graph, 0...1, while hovering.
    @State private var hoverX: Double?
    @State private var graphWidth: CGFloat = 1

    private var start: Date { resetsAt.addingTimeInterval(-kind.duration) }

    /// Readings inside this window, falling back to the current value at `now`.
    private var readingSamples: [UsageSample] {
        let inWindow = samples.filter { $0.date >= start && $0.date <= resetsAt }
        return inWindow.isEmpty ? [UsageSample(date: min(max(now, start), resetsAt), utilization: current)] : inWindow
    }

    private func graphPoint(_ sample: UsageSample) -> GraphPoint {
        GraphPoint(x: sample.date.timeIntervalSince(start) / kind.duration, y: sample.utilization)
    }

    var body: some View {
        let readingSamples = readingSamples
        let readings = readingSamples.map(graphPoint)
        let yMax = max(100, readings.map(\.y).max() ?? 0)
        let hovered = hoverX.flatMap { GraphMath.nearestIndex(in: readings, toX: $0) }
        let days = kind == .session || dayMarkers == .off
            ? [] : GraphMath.days(from: start, to: resetsAt, calendar: .current)

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

                // Day lines at local midnights, behind the data.
                for day in days.dropFirst() {
                    var line = Path()
                    line.move(to: CGPoint(x: size.width * day.start, y: 0))
                    line.addLine(to: CGPoint(x: size.width * day.start, y: size.height))
                    context.stroke(line, with: .color(.white.opacity(0.09)), lineWidth: 0.5)
                }

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

                // Hovered reading: a guide line and a ringed dot in the zone color.
                if let hovered {
                    let p = measured[hovered]
                    var guide = Path()
                    guide.move(to: CGPoint(x: p.x, y: 0))
                    guide.addLine(to: CGPoint(x: p.x, y: size.height))
                    context.stroke(guide, with: .color(.white.opacity(0.3)), lineWidth: 0.5)
                    let ring = CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
                    context.fill(Path(ellipseIn: ring), with: .color(color.color))
                    context.stroke(Path(ellipseIn: ring), with: .color(.white), lineWidth: 1.25)
                }
            }
            .frame(minHeight: height ?? Self.minFlexibleHeight, maxHeight: height ?? .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverX = Double(location.x / max(graphWidth, 1))
                case .ended:
                    hoverX = nil
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { graphWidth = $0 }

            if dayMarkers == .linesAndNames && !days.isEmpty {
                Canvas { context, size in
                    for day in days where (day.end - day.start) * size.width >= Self.minDayNameWidth {
                        let isToday = Calendar.current.isDate(day.date, inSameDayAs: now)
                        let name = Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 8, weight: isToday ? .semibold : .medium))
                            .foregroundStyle(textColor.opacity(isToday ? 0.7 : 0.35))
                        context.draw(name, at: CGPoint(x: size.width * (day.start + day.end) / 2, y: size.height / 2))
                    }
                }
                .frame(height: Self.dayNameHeight)
            }

            Group {
                if let hovered {
                    let reading = readings[hovered]
                    Text(detail(readingSamples[hovered], pace: GraphMath.value(of: pace, at: reading.x)))
                        .foregroundStyle(textColor.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: alignment(forX: reading.x))
                } else {
                    HStack {
                        Text(label(start))
                        Spacer()
                        Text(label(resetsAt))
                    }
                    .foregroundStyle(textColor.opacity(0.3))
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    /// "2:14 PM · 42% · pace 38%" for the session; weekly readings add the weekday.
    private func detail(_ sample: UsageSample, pace: Double?) -> String {
        let when = kind == .session ? Format.time(sample.date) : Format.weekdayTime(sample.date)
        var parts = [when, Format.percent(sample.utilization)]
        if let pace { parts.append("pace " + Format.percent(pace)) }
        return parts.joined(separator: " · ")
    }

    /// Keeps the hover label under the point without running off either edge.
    private func alignment(forX x: Double) -> Alignment {
        if x < 1.0 / 3 { return .leading }
        if x > 2.0 / 3 { return .trailing }
        return .center
    }

    /// Session ends show the time; weekly ends add the weekday ("Sat 4 AM").
    private func label(_ date: Date) -> String {
        kind == .session ? Format.time(date) : date.formatted(.dateTime.weekday(.abbreviated).hour())
    }
}
