import SwiftUI
import WidgetKit
import PaceBarCore

/// Medium and large: which Claude Code chats need you, are working, or still have a warm
/// prompt cache. Reads `chats.json`, which the app writes while the setting is on.
struct ChatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PaceBarChats", provider: ChatsProvider()) { entry in
            ChatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Code Chats")
        .description("Which chats need you, which are working, and how long each idle chat's cache stays warm.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ChatsEntry: TimelineEntry {
    let date: Date
    /// Nil until PaceBar has written its first board.
    let board: ChatBoard?
    /// The app stopped writing the board without saying it quit.
    let stale: Bool
}

/// Lays out a minute-by-minute timeline from one board, plus an entry at each cache expiry, so
/// countdowns tick and chats go cold on time without the app redrawing the widget.
struct ChatsProvider: TimelineProvider {
    static let step: TimeInterval = 60
    static let span: TimeInterval = 60 * 60

    func placeholder(in context: Context) -> ChatsEntry {
        ChatsEntry(date: Date(), board: .sample(now: Date()), stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ChatsEntry) -> Void) {
        let now = Date()
        let stored = WidgetSnapshotStore()?.readBoard()
        // The gallery shows sample chats until there's something real to show.
        let board = context.isPreview && stored?.feed != .live ? .sample(now: now) : stored
        completion(ChatsEntry(date: now, board: board, stale: board?.isStale(readAt: now) ?? false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChatsEntry>) -> Void) {
        let now = Date()
        let board = WidgetSnapshotStore()?.readBoard()
        let stale = board?.isStale(readAt: now) ?? false
        // Nothing moves on a board without chats; check back in an hour.
        guard let board, board.feed == .live, !board.chats.isEmpty else {
            completion(Timeline(entries: [ChatsEntry(date: now, board: board, stale: stale)], policy: .after(now.addingTimeInterval(Self.span))))
            return
        }
        let end = now.addingTimeInterval(Self.span)
        let minutes = stride(from: 0, through: Self.span, by: Self.step).map { now.addingTimeInterval($0) }
        let dates = Set(minutes + board.expiries(after: now).filter { $0 < end }).sorted()
        let entries = dates.map { ChatsEntry(date: $0, board: board, stale: stale || board.isStale(readAt: $0)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension ChatBoard {
    /// Believable chats for the widget gallery and placeholders.
    static func sample(now: Date) -> ChatBoard {
        func chat(_ id: Int32, _ title: String, _ folder: String?, _ activity: Activity, _ reason: String? = nil, ago: TimeInterval) -> Chat {
            Chat(id: id, title: title, folder: folder, activity: activity, reason: reason, since: now.addingTimeInterval(-ago))
        }
        return ChatBoard(
            feed: .live, observedAt: now, cacheLifetime: defaultCacheLifetime,
            theme: Theme.preset(.default).widgetColors,
            chats: [
                chat(1, "Release notes", "pacebar", .needsYou, "dialog open", ago: 40),
                chat(2, "n8n-workflows", nil, .working, ago: 4 * 60),
                chat(3, "curvelog", nil, .idle, ago: 19 * 60),
                chat(4, "Magic world bugs", "ridebook", .idle, ago: 53 * 60),
                chat(5, "ridebook", nil, .idle, ago: 3 * 3600),
                chat(6, "serve-forecasttool", nil, .idle, ago: 26 * 3600),
            ]
        )
    }
}
