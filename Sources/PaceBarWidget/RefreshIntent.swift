import AppIntents
import Foundation
import PaceBarCore

/// The widgets' refresh button. Posts the App Group's refresh notification, which PaceBar
/// answers like opening the popover: it redraws the widgets with what it has, then fetches if
/// its data is over 30 seconds old. The notification carries no data.
struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource { "Refresh PaceBar" }
    static var description: IntentDescription { "Asks PaceBar to update your usage now." }
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        if let name = WidgetSnapshotStore.refreshNotificationName() {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true
            )
        }
        return .result()
    }
}
