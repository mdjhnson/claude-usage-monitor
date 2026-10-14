import Foundation
import WidgetKit
import PaceBarCore

struct UsageEntry: TimelineEntry {
    let date: Date
    /// Nil until PaceBar has written its first snapshot.
    let snapshot: WidgetSnapshot?
    /// The small widget's chosen limit, or the medium widget's chosen graph, as a
    /// `WindowKind.id` (or `LimitEntity.bothID`). Nil for the large widget.
    var limitID: String? = nil

    /// Entries at now and every `step` after, each recomputing pacing for its own time.
    static func timeline(_ snapshot: WidgetSnapshot?, limitID: String? = nil, now: Date = Date()) -> Timeline<UsageEntry> {
        let entries = (0...Provider.steps).map {
            UsageEntry(date: now.addingTimeInterval(Double($0) * Provider.step), snapshot: snapshot, limitID: limitID)
        }
        // The app also asks for a reload when something visible changes.
        return Timeline(entries: entries, policy: .atEnd)
    }
}

/// Reads the app's snapshot and lays out a short timeline from it. Each entry recomputes pacing
/// for its own time, so zones and the pace line move on even while the numbers hold still.
struct Provider: TimelineProvider {
    /// How far apart entries are, and how many follow the first.
    static let step: TimeInterval = 15 * 60
    static let steps = 4

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .sample(now: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let now = Date()
        let stored = WidgetSnapshotStore()?.read()
        // The gallery shows sample data until there's something real to show.
        completion(UsageEntry(date: now, snapshot: context.isPreview ? stored ?? .sample(now: now) : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        completion(UsageEntry.timeline(WidgetSnapshotStore()?.read()))
    }
}

/// The small widget's provider: the same timeline, carrying the chosen limit.
struct LimitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .sample(now: Date()))
    }

    func snapshot(for configuration: LimitWidgetIntent, in context: Context) async -> UsageEntry {
        let now = Date()
        let stored = WidgetSnapshotStore()?.read()
        return UsageEntry(date: now, snapshot: context.isPreview ? stored ?? .sample(now: now) : stored,
                          limitID: configuration.limit?.id)
    }

    func timeline(for configuration: LimitWidgetIntent, in context: Context) async -> Timeline<UsageEntry> {
        UsageEntry.timeline(WidgetSnapshotStore()?.read(), limitID: configuration.limit?.id)
    }
}

/// The medium widget's provider: the same timeline, carrying the chosen graph.
struct GraphProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .sample(now: Date()))
    }

    func snapshot(for configuration: GraphWidgetIntent, in context: Context) async -> UsageEntry {
        let now = Date()
        let stored = WidgetSnapshotStore()?.read()
        return UsageEntry(date: now, snapshot: context.isPreview ? stored ?? .sample(now: now) : stored,
                          limitID: configuration.graph?.id)
    }

    func timeline(for configuration: GraphWidgetIntent, in context: Context) async -> Timeline<UsageEntry> {
        UsageEntry.timeline(WidgetSnapshotStore()?.read(), limitID: configuration.graph?.id)
    }
}

extension WidgetSnapshot {
    /// Believable numbers for the widget gallery and placeholders.
    static func sample(now: Date) -> WidgetSnapshot {
        let sessionReset = now.addingTimeInterval(2 * 3600 + 14 * 60)
        let weeklyReset = now.addingTimeInterval(3 * 86_400 + 5 * 3600)
        let sessionStart = sessionReset.addingTimeInterval(-WindowKind.sessionDuration)
        let weeklyStart = weeklyReset.addingTimeInterval(-WindowKind.weeklyDuration)
        func ramp(from start: Date, to end: Date, upTo value: Double) -> [UsageSample] {
            (0...12).map { i in
                let f = Double(i) / 12
                return UsageSample(date: start.addingTimeInterval(end.timeIntervalSince(start) * f), utilization: value * f * f)
            }
        }
        return WidgetSnapshot(
            fetchedAt: now,
            refreshInterval: 180,
            hasError: false,
            windows: [
                Window(kind: .session, utilization: 52, resetsAt: sessionReset,
                       samples: ramp(from: sessionStart.addingTimeInterval(1800), to: now, upTo: 52)),
                Window(kind: .weekly, utilization: 38, resetsAt: weeklyReset,
                       samples: ramp(from: weeklyStart.addingTimeInterval(3600), to: now, upTo: 38)),
            ],
            display: Display(
                margin: 10, schedule: .default, colorMode: ColorMode.pacing.rawValue, warningAt: 60, criticalAt: 85,
                usageGraph: true, weeklyDayMarkers: WeeklyDayMarkers.linesAndNames.rawValue,
                theme: Theme.preset(.default).widgetColors
            )
        )
    }
}
