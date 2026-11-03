import Foundation

/// One Claude Code chat's state file, `~/.claude/sessions/<pid>.json`, as Claude Code writes it.
/// Only the fields PaceBar uses are decoded; everything else in the file (session and bridge IDs,
/// socket paths) is ignored and never kept.
public struct SessionFile: Decodable, Equatable, Sendable {
    public var pid: Int32?
    public var cwd: String?
    public var name: String?
    /// "derived" for a name Claude Code made from the folder; "user" or "peer" when someone named it.
    public var nameSource: String?
    /// "busy", "idle" or "waiting".
    public var status: String?
    /// Set while waiting: "input needed", "dialog open", "sandbox request" and so on.
    public var waitingFor: String?
    /// Milliseconds since 1970.
    public var statusUpdatedAt: Double?
    public var startedAt: Double?
    /// The process start time in UTC, as `ps -o lstart` prints it: "Tue Nov  3 22:18:38 2026".
    public var procStart: String?

    public init(
        pid: Int32?, cwd: String? = nil, name: String? = nil, nameSource: String? = nil, status: String? = nil,
        waitingFor: String? = nil, statusUpdatedAt: Double? = nil, startedAt: Double? = nil, procStart: String? = nil
    ) {
        self.pid = pid
        self.cwd = cwd
        self.name = name
        self.nameSource = nameSource
        self.status = status
        self.waitingFor = waitingFor
        self.statusUpdatedAt = statusUpdatedAt
        self.startedAt = startedAt
        self.procStart = procStart
    }

    /// Nil for anything that isn't a session file with a PID.
    public static func decode(_ data: Data) -> SessionFile? {
        guard let file = try? JSONDecoder().decode(SessionFile.self, from: data), file.pid != nil else { return nil }
        return file
    }

    /// Only `<pid>.json`. The `<pid>.<hash>.key` files beside them are never opened.
    public static func isSessionFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        let stem = name.dropLast(5)
        return !stem.isEmpty && stem.count <= 10 && stem.allSatisfy(\.isASCII) && stem.allSatisfy(\.isNumber)
    }

    /// Largest file read; a real one is under 1 KB.
    public static let maxFileSize = 64 * 1024
}

/// Tells a live chat from a PID the system has since handed to another process.
public enum ProcessIdentity {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f
    }()

    /// `procStart` parsed, or nil when it's missing or in another shape.
    public static func date(procStart: String) -> Date? {
        let collapsed = procStart.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return formatter.date(from: collapsed)
    }

    /// Whether the running process with this PID is the one that wrote the file. A file without a
    /// readable `procStart` gets the benefit of the doubt.
    public static func matches(procStart: String?, startTime: Date) -> Bool {
        guard let procStart, let recorded = date(procStart: procStart) else { return true }
        return abs(recorded.timeIntervalSince(startTime)) < 2
    }
}

/// The open Claude Code chats, for the Claude Code Chats widget. The app writes it to the App
/// Group container; the sandboxed widget reads it.
///
/// Chat titles, folder names, states and times only: no session IDs, socket paths, full paths,
/// transcript content, or anything from the Keychain.
public struct ChatBoard: Codable, Equatable, Sendable {
    public enum Activity: String, Codable, Sendable {
        case needsYou, working, idle
    }

    public struct Chat: Codable, Equatable, Sendable, Identifiable {
        /// The process ID.
        public let id: Int32
        public let title: String
        /// The project folder's name, when it isn't already the title.
        public let folder: String?
        public let activity: Activity
        /// What a chat that needs you is waiting on, as Claude Code words it ("dialog open").
        public let reason: String?
        /// When the chat entered its current activity.
        public let since: Date

        public init(id: Int32, title: String, folder: String?, activity: Activity, reason: String?, since: Date) {
            self.id = id
            self.title = title
            self.folder = folder
            self.activity = activity
            self.reason = reason
            self.since = since
        }
    }

    /// A chat's state at a moment, with idle split by whether the prompt cache is still warm.
    public enum State: Equatable, Sendable {
        case needsYou
        case working
        case cached(expires: Date)
        case cold

        var rank: Int {
            switch self {
            case .needsYou: 0
            case .working: 1
            case .cached: 2
            case .cold: 3
            }
        }
    }

    /// The two cache lifetimes Claude Code uses: an hour on Claude plans, five minutes on API keys.
    public static let cacheLifetimes: [TimeInterval] = [3600, 300]
    public static let defaultCacheLifetime: TimeInterval = 3600
    public static let maxChats = 30
    public static let maxTitleLength = 60

    /// Where the board stands, so the widget can say what to do when there's nothing to show.
    public enum Feed: String, Codable, Sendable {
        /// The setting is off; PaceBar isn't reading chats.
        case off
        /// PaceBar is reading chats.
        case live
        /// PaceBar quit, so the chats it last saw may have moved on.
        case closed
    }

    /// While live, the app rewrites the file at least this often, even when nothing changed.
    public static let heartbeat: TimeInterval = 10 * 60
    /// A live board older than this when the widget reads it means the app stopped without saying so.
    public static let staleAge: TimeInterval = 2 * heartbeat + 60

    public let feed: Feed
    public let observedAt: Date
    public let cacheLifetime: TimeInterval
    /// The app's theme as `0xRRGGBB` by token name, as in `WidgetSnapshot.Display.theme`.
    public let theme: [String: UInt32]
    /// Most urgent first; see `sorted(at:)`.
    public let chats: [Chat]

    public init(feed: Feed, observedAt: Date, cacheLifetime: TimeInterval, theme: [String: UInt32], chats: [Chat]) {
        self.feed = feed
        self.observedAt = observedAt
        self.cacheLifetime = cacheLifetime
        self.theme = theme
        self.chats = chats
    }

    /// A board with no chats that only says the setting is off, or that PaceBar quit.
    public static func empty(_ feed: Feed, now: Date, theme: [String: UInt32]) -> ChatBoard {
        ChatBoard(feed: feed, observedAt: now, cacheLifetime: defaultCacheLifetime, theme: theme, chats: [])
    }

    /// True when a live board's app has evidently stopped writing it.
    public func isStale(readAt now: Date) -> Bool {
        feed == .live && now.timeIntervalSince(observedAt) > Self.staleAge
    }

    /// Builds the board from live chats' files. The caller drops files whose process has ended.
    public static func make(
        from files: [SessionFile], cacheLifetime: TimeInterval, theme: [String: UInt32], now: Date
    ) -> ChatBoard {
        let all = ChatBoard(
            feed: .live, observedAt: now, cacheLifetime: cacheLifetime, theme: theme,
            chats: files.compactMap { chat(from: $0, now: now) }
        )
        return ChatBoard(
            feed: .live, observedAt: now, cacheLifetime: cacheLifetime, theme: theme,
            chats: Array(all.sorted(at: now).prefix(maxChats))
        )
    }

    static func chat(from file: SessionFile, now: Date) -> Chat? {
        guard let pid = file.pid else { return nil }
        let folder = file.cwd.flatMap { cwd -> String? in
            let last = URL(fileURLWithPath: cwd).lastPathComponent
            return last.isEmpty || last == "/" ? nil : last
        }
        let named = ["user", "peer"].contains(file.nameSource ?? "") ? file.name?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let title = clip(named.flatMap { $0.isEmpty ? nil : $0 } ?? folder ?? "Claude Code")

        let activity: Activity
        switch file.status {
        case "waiting": activity = .needsYou
        case "busy": activity = .working
        default: activity = .idle
        }
        let millis = file.statusUpdatedAt ?? file.startedAt
        return Chat(
            id: pid,
            title: title,
            folder: folder.map(clip).flatMap { $0 == title ? nil : $0 },
            activity: activity,
            reason: activity == .needsYou ? file.waitingFor.map(clip) : nil,
            since: millis.map { Date(timeIntervalSince1970: $0 / 1000) } ?? now
        )
    }

    private static func clip(_ text: String) -> String {
        text.count > maxTitleLength ? String(text.prefix(maxTitleLength - 1)) + "…" : text
    }

    public func state(of chat: Chat, at now: Date) -> State {
        switch chat.activity {
        case .needsYou: return .needsYou
        case .working: return .working
        case .idle:
            let expires = chat.since.addingTimeInterval(cacheLifetime)
            return now < expires ? .cached(expires: expires) : .cold
        }
    }

    /// Needs you, oldest first; working, longest first; cached, soonest to expire first; cold,
    /// most recent first. The PID breaks ties so the order holds still between redraws.
    public func sorted(at now: Date) -> [Chat] {
        chats.sorted { a, b in
            let sa = state(of: a, at: now), sb = state(of: b, at: now)
            if sa.rank != sb.rank { return sa.rank < sb.rank }
            if a.since != b.since { return sa == .cold ? a.since > b.since : a.since < b.since }
            return a.id < b.id
        }
    }

    /// The chats in each state at `now`, most urgent first.
    public func grouped(at now: Date) -> (needsYou: [Chat], working: [Chat], cached: [Chat], cold: [Chat]) {
        var groups: (needsYou: [Chat], working: [Chat], cached: [Chat], cold: [Chat]) = ([], [], [], [])
        for chat in sorted(at: now) {
            switch state(of: chat, at: now) {
            case .needsYou: groups.needsYou.append(chat)
            case .working: groups.working.append(chat)
            case .cached: groups.cached.append(chat)
            case .cold: groups.cold.append(chat)
            }
        }
        return groups
    }

    /// When some chat's cache goes cold after `now`, soonest first: moments the widget redraws.
    public func expiries(after now: Date) -> [Date] {
        chats.compactMap { chat in
            if case let .cached(expires) = state(of: chat, at: now) { return expires }
            return nil
        }
        .sorted()
    }

    /// What the widget shows apart from countdowns, to tell a change worth a reload from one
    /// the widget's own timeline already covers.
    public var visibleState: [Chat] {
        chats.sorted { $0.id < $1.id }
    }

    /// The IDs of chats that need you. A change here reloads the widget straight away.
    public var needsYouIDs: Set<Int32> {
        Set(chats.filter { $0.activity == .needsYou }.map(\.id))
    }
}
