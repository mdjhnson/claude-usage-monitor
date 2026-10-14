import SwiftUI
import WidgetKit
import PaceBarCore

/// PaceBar's desktop and Notification Center widgets. Sandboxed, with no network access: it only
/// reads the snapshot the app writes to their shared App Group container.
@main
struct PaceBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        LimitWidget()
        UsageWidget()
    }
}

/// Small: one limit as a ring. Edit Widget chooses which.
struct LimitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PaceBarLimit", intent: LimitWidgetIntent.self, provider: LimitProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Limit")
        .description("One limit and whether you're on pace. Choose which with Edit Widget.")
        .supportedFamilies([.systemSmall])
    }
}

/// Medium and large: the popover's limits with bars and graphs.
struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PaceBarUsage", provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Your Claude limits and whether you're on pace.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
