import SwiftUI
import WidgetKit
import PaceBarCore

/// PaceBar's desktop and Notification Center widgets. Sandboxed, with no network access: it only
/// reads the snapshot the app writes to their shared App Group container.
@main
struct PaceBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Your Claude limits and whether you're on pace.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
