import SwiftUI
import WidgetKit
import PaceBarCore

/// Everything one entry's views need, resolved once from the snapshot.
struct WidgetModel {
    let snapshot: WidgetSnapshot
    let now: Date
    let theme: Theme
    let colorMode: ColorMode
    let dayMarkers: WeeklyDayMarkers
    let stale: Bool

    init(snapshot: WidgetSnapshot, now: Date) {
        self.snapshot = snapshot
        self.now = now
        theme = .widget(snapshot.display.theme)
        colorMode = ColorMode(rawValue: snapshot.display.colorMode) ?? .pacing
        dayMarkers = WeeklyDayMarkers(rawValue: snapshot.display.weeklyDayMarkers) ?? .linesAndNames
        stale = snapshot.isStale(now: now)
    }

    var text: Color { theme.textColor }
    var dim: Double { stale ? 0.45 : 1 }

    func pacing(_ window: WidgetSnapshot.Window) -> PacingResult? {
        snapshot.pacing(for: window, now: now)
    }

    /// The percentage color, chosen the same way as the popover's.
    func tint(_ window: WidgetSnapshot.Window, _ pacing: PacingResult?) -> ThemeColor {
        theme.tint(
            utilization: window.utilization, pacing: pacing, mode: colorMode,
            warningAt: snapshot.display.warningAt, criticalAt: snapshot.display.criticalAt
        )
    }

    /// The graph's readings and pace line, when the graph is on and the window has a reset time.
    func graph(_ window: WidgetSnapshot.Window) -> (resetsAt: Date, pace: [GraphPoint])? {
        guard snapshot.display.usageGraph, let resetsAt = window.resetsAt,
              let pace = snapshot.paceCurve(for: window) else { return nil }
        return (resetsAt, pace)
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        let model = entry.snapshot.map { WidgetModel(snapshot: $0, now: entry.date) }
        let theme = model?.theme ?? .preset(.default)

        Group {
            if let model, !model.snapshot.windows.isEmpty {
                switch family {
                case .systemSmall: SmallUsageView(model: model, limitID: entry.limitID)
                case .systemMedium: MediumUsageView(model: model, graphID: entry.limitID)
                default: LargeUsageView(model: model)
                }
            } else {
                EmptyUsageView(
                    message: model == nil
                        ? "Open PaceBar to start."
                        : "No limits to show. Choose some in PaceBar's Settings › Windows.",
                    text: theme.textColor
                )
            }
        }
        .containerBackground(for: .widget) { theme.popoverBackground }
    }
}

// MARK: Sizes

/// The chosen limit as a ring. Falls back to the 5-hour session, then the first shown limit,
/// when the chosen one isn't in the snapshot (hidden in the popover, or not reported).
struct SmallUsageView: View {
    let model: WidgetModel
    let limitID: String?

    var body: some View {
        let windows = model.snapshot.windows
        let window = windows.first { $0.kind.id == limitID } ?? windows.first { $0.kind == .session } ?? windows[0]
        let pacing = model.pacing(window)
        let tint = model.tint(window, pacing)

        VStack(alignment: .leading, spacing: 6) {
            WindowTitle(kind: window.kind, model: model)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(max(window.utilization, 0), 100) / 100)
                    .stroke(tint.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(Format.percent(window.utilization))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint.color)
                    if let pacing {
                        Text(pacing.zone.title)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(model.theme.zone(pacing.zone).color)
                    }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(model.dim)

            Footer(window: window, model: model)
        }
    }
}

/// Up to two windows as bars, with the chosen graph, or the session's and weekly's, beside them.
struct MediumUsageView: View {
    let model: WidgetModel
    /// A `WindowKind.id`, or `LimitEntity.bothID`. Nil means the session's graph.
    let graphID: String?

    /// The windows whose graphs to draw. A choice missing from the snapshot falls back to the
    /// session, then the first shown window.
    private var graphed: [WidgetSnapshot.Window] {
        let all = model.snapshot.windows
        func window(_ kind: WindowKind) -> WidgetSnapshot.Window? { all.first { $0.kind == kind } }
        if graphID == LimitEntity.bothID {
            let both = [window(.session), window(.weekly)].compactMap { $0 }
            if !both.isEmpty { return both }
        }
        let chosen = all.first { $0.kind.id == graphID } ?? window(.session) ?? all[0]
        return [chosen]
    }

    var body: some View {
        let windows = Array(model.snapshot.windows.prefix(2))
        let graphs = graphed.compactMap { window in model.graph(window).map { (window, $0) } }
        // Two graphs share the column, so they're shorter; day names never fit at this width.
        let dayMarkers: WeeklyDayMarkers = model.dayMarkers == .off ? .off : .lines

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(windows, id: \.kind) { window in
                        BarRow(window: window, model: model, showsCountdown: true)
                    }
                }
                .frame(maxWidth: .infinity)

                if !graphs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(graphs, id: \.0.kind) { window, graph in
                            VStack(alignment: .leading, spacing: graphs.count > 1 ? 2 : 4) {
                                WindowTitle(kind: window.kind, model: model)
                                Graph(window: window, graph: graph, model: model, dayMarkers: dayMarkers,
                                      height: graphs.count > 1 ? 24 : UsageGraph.height)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            if model.stale { StaleLine(model: model) }
        }
    }
}

/// Up to three windows, each with its bar, zone and graph.
struct LargeUsageView: View {
    let model: WidgetModel

    var body: some View {
        let windows = Array(model.snapshot.windows.prefix(3))
        // Three windows only fit with shorter graphs and no day names or cooling lines.
        let crowded = windows.count >= 3
        let dayMarkers: WeeklyDayMarkers = crowded && model.dayMarkers == .linesAndNames ? .lines : model.dayMarkers

        VStack(alignment: .leading, spacing: crowded ? 10 : 14) {
            ForEach(windows, id: \.kind) { window in
                let graph = model.graph(window)
                VStack(alignment: .leading, spacing: 4) {
                    // A graph's axis already ends at the reset time.
                    BarRow(window: window, model: model, showsCountdown: graph == nil, showsZone: true)
                    if !crowded, let pacing = model.pacing(window), let cooling = pacing.coolingDate,
                       pacing.zone == .warning || pacing.zone == .hot {
                        Text(Format.cooling(cooling, now: model.now))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(model.text.opacity(0.4))
                    }
                    if let graph {
                        Graph(window: window, graph: graph, model: model, dayMarkers: dayMarkers,
                              height: crowded ? 34 : UsageGraph.height)
                    }
                }
            }
            Spacer(minLength: 0)
            if model.stale { StaleLine(model: model) }
        }
    }
}

// MARK: Pieces

struct WindowTitle: View {
    let kind: WindowKind
    let model: WidgetModel

    var body: some View {
        Text(kind.title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(model.text.opacity(0.45))
            .lineLimit(1)
    }
}

/// Title, countdown and percentage over the pacing bar.
struct BarRow: View {
    let window: WidgetSnapshot.Window
    let model: WidgetModel
    var showsCountdown = false
    var showsZone = false

    var body: some View {
        let pacing = model.pacing(window)
        let tint = model.tint(window, pacing)

        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                WindowTitle(kind: window.kind, model: model)
                Spacer(minLength: 4)
                if showsZone, let pacing {
                    ZonePill(title: pacing.zone.title, color: model.theme.zone(pacing.zone).color)
                        .opacity(model.dim)
                }
                Text(Format.percent(window.utilization))
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint.color)
                    .opacity(model.dim)
            }
            if let pacing {
                PacingBar(
                    actual: pacing.actualUsage, markerFraction: pacing.markerFraction,
                    zoneColor: model.theme.zone(pacing.zone), offTimeRanges: pacing.offTimeRanges,
                    isOffTime: pacing.isOffTime, animated: false
                )
                .opacity(model.dim)
            }
            if showsCountdown, let resetsAt = window.resetsAt {
                Text(Format.resetCountdown(kind: window.kind, resetsAt: resetsAt, now: model.now))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(model.text.opacity(0.35))
                    .lineLimit(1)
            }
        }
    }
}

struct Graph: View {
    let window: WidgetSnapshot.Window
    let graph: (resetsAt: Date, pace: [GraphPoint])
    let model: WidgetModel
    let dayMarkers: WeeklyDayMarkers
    var height = UsageGraph.height

    var body: some View {
        let pacing = model.pacing(window)
        UsageGraph(
            samples: window.samples, pace: graph.pace, resetsAt: graph.resetsAt, kind: window.kind,
            current: window.utilization, color: pacing.map { model.theme.zone($0.zone) } ?? model.tint(window, nil),
            textColor: model.text, now: model.now, dayMarkers: dayMarkers, height: height
        )
        .opacity(model.dim)
    }
}

/// The small widget's bottom line: when it resets, or how old the data is once stale.
struct Footer: View {
    let window: WidgetSnapshot.Window
    let model: WidgetModel

    var body: some View {
        if model.stale {
            StaleLine(model: model)
        } else if let resetsAt = window.resetsAt {
            Text(Format.resetCountdown(kind: window.kind, resetsAt: resetsAt, now: model.now))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(model.text.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// "Updated 25 min ago", matching the popover's stale line.
struct StaleLine: View {
    let model: WidgetModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
            Text("Updated \(Format.age(since: model.snapshot.fetchedAt, now: model.now))")
        }
        .font(.system(size: 10))
        .foregroundStyle(model.text.opacity(0.45))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

struct EmptyUsageView: View {
    let message: String
    let text: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 22))
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(text.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
