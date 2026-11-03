import Foundation
import WidgetKit
import PaceBarCore

/// Feeds the Claude Code Chats widget. While the setting is on, it reads the chats' state files
/// every few seconds, writes `chats.json` to the App Group container when something visible
/// changed, and asks WidgetKit to redraw that one widget. Titles, folder names, states and times only.
@MainActor
final class ChatBoardPublisher {
    static let widgetKind = "PaceBarChats"
    /// How often the state files are checked. Each check is a folder listing plus a `stat` per
    /// chat; only files that changed are read.
    static let pollInterval: Duration = .seconds(5)
    /// Ordinary changes (a chat starting or finishing a turn) redraw at most this often, which
    /// keeps the widget inside WidgetKit's daily reload budget. A chat starting or stopping
    /// waiting on you redraws at once. Countdowns and caches going cold need no redraw.
    static let minReloadGap: TimeInterval = 60

    /// What the widget shows apart from what its own timeline works out.
    private struct Visible: Equatable {
        let feed: ChatBoard.Feed
        let cacheLifetime: TimeInterval
        let theme: [String: UInt32]
        let chats: [ChatBoard.Chat]

        init(_ board: ChatBoard) {
            feed = board.feed
            cacheLifetime = board.cacheLifetime
            theme = board.theme
            chats = board.visibleState
        }
    }

    private let settings: SettingsStore
    private let file = WidgetSnapshotStore()
    private let reader = ChatSessionReader()
    private var task: Task<Void, Never>?
    private var lastWritten: Visible?
    private var lastWrite: Date?
    private var lastReloaded: Visible?
    private var lastReloadedNeedsYou: Set<Int32> = []
    private var lastReload: Date?

    init(settings: SettingsStore) {
        self.settings = settings
        observe()
        apply()
    }

    /// Tells the widget PaceBar quit, so it doesn't keep showing chats as they last were.
    func stop() {
        task?.cancel()
        task = nil
        guard settings.showClaudeChats else { return }
        publish(.empty(.closed, now: Date(), theme: settings.theme.widgetColors), force: true)
    }

    private func observe() {
        withObservationTracking {
            _ = settings.showClaudeChats
            _ = settings.chatCacheLifetime
            _ = settings.theme
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.apply()
                self?.observe()
            }
        }
    }

    /// Starts or stops reading to match the setting. A change restarts the loop, which checks
    /// straight away.
    private func apply() {
        task?.cancel()
        task = nil
        guard settings.showClaudeChats else {
            publish(.empty(.off, now: Date(), theme: settings.theme.widgetColors))
            return
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func check() async {
        let files = await reader.scan()
        guard !Task.isCancelled, settings.showClaudeChats else { return }
        publish(ChatBoard.make(
            from: files, cacheLifetime: settings.chatCacheLifetime, theme: settings.theme.widgetColors, now: Date()
        ))
    }

    private func publish(_ board: ChatBoard, force: Bool = false) {
        guard let file else { return }
        let now = Date()
        let visible = Visible(board)

        // Rewritten on change, and on the heartbeat so the widget can tell PaceBar is still running.
        let heartbeatDue = lastWrite.map { now.timeIntervalSince($0) >= ChatBoard.heartbeat } ?? true
        if force || visible != lastWritten || heartbeatDue {
            // Best effort: the widget keeps its last good file.
            guard (try? file.write(board)) != nil else { return }
            lastWritten = visible
            lastWrite = now
        }

        guard visible != lastReloaded else { return }
        let urgent = force || lastReloaded == nil || board.needsYouIDs != lastReloadedNeedsYou
            || visible.feed != lastReloaded?.feed || visible.cacheLifetime != lastReloaded?.cacheLifetime
            || visible.theme != lastReloaded?.theme
        let gapPassed = lastReload.map { now.timeIntervalSince($0) >= Self.minReloadGap } ?? true
        // A change held back by the gap goes out on a later check, since it's compared with
        // what the widget last reloaded with.
        guard urgent || gapPassed else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
        lastReloaded = visible
        lastReloadedNeedsYou = board.needsYouIDs
        lastReload = now
    }
}
