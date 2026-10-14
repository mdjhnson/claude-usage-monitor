import Foundation
import WidgetKit
import PaceBarCore

struct UsageEntry: TimelineEntry {
    let date: Date
    /// Nil until PaceBar has written its first snapshot.
    let snapshot: WidgetSnapshot?
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
        let now = Date()
        let stored = WidgetSnapshotStore()?.read()
        let entries = (0...Self.steps).map {
            UsageEntry(date: now.addingTimeInterval(Double($0) * Self.step), snapshot: stored)
        }
        // The app also asks for a reload when something visible changes.
        completion(Timeline(entries: entries, policy: .atEnd))
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
