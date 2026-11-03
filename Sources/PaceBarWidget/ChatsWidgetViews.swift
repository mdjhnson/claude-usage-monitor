import SwiftUI
import WidgetKit
import PaceBarCore

/// Everything one entry's views need, resolved once from the board.
struct ChatsModel {
    let board: ChatBoard
    let now: Date
    let theme: Theme
    let stale: Bool
    let groups: (needsYou: [ChatBoard.Chat], working: [ChatBoard.Chat], cached: [ChatBoard.Chat], cold: [ChatBoard.Chat])

    init(board: ChatBoard, now: Date, stale: Bool) {
        self.board = board
        self.now = now
        self.stale = stale
        theme = .widget(board.theme)
        groups = board.grouped(at: now)
    }

    var text: Color { theme.textColor }
    var dim: Double { stale ? 0.45 : 1 }

    /// Chats that need you, are working or are cached, most urgent first. Cold ones are only counted.
    var active: [ChatBoard.Chat] { groups.needsYou + groups.working + groups.cached }

    func state(_ chat: ChatBoard.Chat) -> ChatBoard.State { board.state(of: chat, at: now) }

    /// A cache with under this long left burns in the warning color.
    static let lowCache: TimeInterval = 10 * 60

    func color(_ state: ChatBoard.State) -> Color {
        switch state {
        case .needsYou: theme.warning.color
        case .working: theme.onTrack.color
        case let .cached(expires): (expires.timeIntervalSince(now) < Self.lowCache ? theme.warning : theme.chill).color
        case .cold: text.opacity(0.35)
        }
    }

    /// Warm cache is a flame, cold is a snowflake. The symbol carries the state without color.
    static func symbol(_ state: ChatBoard.State) -> String {
        switch state {
        case .needsYou: "hand.raised.fill"
        case .working: "ellipsis"
        case .cached: "flame.fill"
        case .cold: "snowflake"
        }
    }

    /// The row's trailing text: "Needs you", "Working 4m", "41m left".
    func label(_ chat: ChatBoard.Chat, _ state: ChatBoard.State) -> String {
        switch state {
        case .needsYou: Self.waitingLabel(chat.reason, for: now.timeIntervalSince(chat.since))
        case .working: "Working \(Format.compactDuration(now.timeIntervalSince(chat.since)))"
        case let .cached(expires): "\(Format.compactDuration(expires.timeIntervalSince(now))) left"
        case .cold: "Cold"
        }
    }

    /// "Waiting 2m" for a dialog such as a permission prompt; otherwise Claude Code's own
    /// reason, which says more: "Input needed", "Sandbox request".
    static func waitingLabel(_ reason: String?, for waited: TimeInterval) -> String {
        switch reason {
        case nil, "dialog open": "Waiting \(Format.compactDuration(waited))"
        case let reason?: reason.prefix(1).uppercased() + reason.dropFirst()
        }
    }

    /// A section's color, which doesn't follow any one chat's countdown.
    func sectionColor(_ activity: ChatBoard.Activity) -> Color {
        switch activity {
        case .needsYou: theme.warning.color
        case .working: theme.onTrack.color
        case .idle: theme.chill.color
        }
    }
}

struct ChatsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ChatsEntry

    var body: some View {
        let theme = entry.board.map { Theme.widget($0.theme) } ?? .preset(.default)

        Group {
            if let board = entry.board, board.feed == .live, !board.chats.isEmpty {
                let model = ChatsModel(board: board, now: entry.date, stale: entry.stale)
                if family == .systemLarge { LargeChatsView(model: model) } else { MediumChatsView(model: model) }
            } else {
                EmptyChatsView(message: Self.emptyMessage(entry.board), text: theme.textColor)
            }
        }
        .containerBackground(for: .widget) { theme.popoverBackground }
    }

    static func emptyMessage(_ board: ChatBoard?) -> String {
        switch board?.feed {
        case nil: "Open PaceBar and turn on Claude Code chats in Settings › General."
        case .off: "Turn on Claude Code chats in PaceBar's Settings › General."
        case .closed: "Open PaceBar to see your Claude Code chats."
        case .live: "No Claude Code chats open."
        }
    }
}

// MARK: Sizes

/// How many rows fit, measured in points, since a cached row with its fuse is taller.
enum ChatsLayout {
    static let rowHeight: CGFloat = 15
    static let fuseHeight: CGFloat = 6
    static let lineHeight: CGFloat = 13
    static let titleHeight: CGFloat = 11

    static func height(_ chat: ChatBoard.Chat, _ model: ChatsModel) -> CGFloat {
        if case .cached = model.state(chat) { return rowHeight + fuseHeight }
        return rowHeight
    }

    /// Takes chats in order while they fit in `available`, keeping room for a "+N more" line
    /// wherever chats are left out. A section that can't fit its title and one row is dropped;
    /// the header still counts its chats.
    static func fit(
        _ sections: [[ChatBoard.Chat]], titled: Bool, available: CGFloat, spacing: CGFloat, sectionSpacing: CGFloat,
        model: ChatsModel
    ) -> [(chats: [ChatBoard.Chat], hidden: Int)] {
        var used: CGFloat = 0
        var result: [(chats: [ChatBoard.Chat], hidden: Int)] = []
        for (index, chats) in sections.enumerated() {
            let lead = (index > 0 ? sectionSpacing : 0) + (titled ? titleHeight + spacing : 0)
            guard let first = chats.first, used + lead + height(first, model) <= available else { break }
            used += lead
            var taken: [ChatBoard.Chat] = []
            for (i, chat) in chats.enumerated() {
                let row = (taken.isEmpty ? 0 : spacing) + height(chat, model)
                let isLast = i == chats.count - 1 && index == sections.count - 1
                let reserve = isLast ? 0 : spacing + lineHeight
                if used + row + reserve <= available || (taken.isEmpty && used + row <= available) {
                    taken.append(chat)
                    used += row
                } else {
                    break
                }
            }
            let hidden = chats.count - taken.count
            if hidden > 0 { used += spacing + lineHeight }
            result.append((taken, hidden))
            if hidden > 0 { break }
        }
        return result
    }
}

/// The header, then as many chats as fit, most urgent first. Cold chats only appear in the
/// header's count.
struct MediumChatsView: View {
    static let spacing: CGFloat = 7
    let model: ChatsModel

    var body: some View {
        GeometryReader { geo in
            let footer = model.stale ? Self.spacing + ChatsLayout.lineHeight : 0
            let available = geo.size.height - ChatsLayout.rowHeight - Self.spacing - footer
            let fitted = ChatsLayout.fit(
                [model.active], titled: false, available: available, spacing: Self.spacing, sectionSpacing: 0, model: model
            ).first

            VStack(alignment: .leading, spacing: Self.spacing) {
                ChatsHeader(model: model)
                if model.active.isEmpty {
                    QuietLine(model: model)
                }
                ForEach(fitted?.chats ?? []) { chat in
                    ChatRow(chat: chat, model: model)
                }
                if let hidden = fitted?.hidden, hidden > 0 {
                    MoreLine(count: hidden, model: model)
                }
                Spacer(minLength: 0)
                if model.stale { ChatsStaleLine(model: model) }
            }
        }
    }
}

/// The header, then a section for each state that has chats, then the cold count.
struct LargeChatsView: View {
    static let spacing: CGFloat = 6
    static let sectionSpacing: CGFloat = 10
    let model: ChatsModel

    var body: some View {
        let sections: [(String, ChatBoard.Activity, [ChatBoard.Chat])] = [
            ("Needs you", .needsYou, model.groups.needsYou), ("Working", .working, model.groups.working),
            ("Cached", .idle, model.groups.cached),
        ].filter { !$0.2.isEmpty }

        GeometryReader { geo in
            let chrome = 2 * (ChatsLayout.rowHeight + Self.sectionSpacing)
            let fitted = ChatsLayout.fit(
                sections.map(\.2), titled: true, available: geo.size.height - chrome,
                spacing: Self.spacing, sectionSpacing: Self.sectionSpacing, model: model
            )

            VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                ChatsHeader(model: model)
                if sections.isEmpty {
                    QuietLine(model: model)
                }
                ForEach(Array(fitted.enumerated()), id: \.offset) { index, section in
                    VStack(alignment: .leading, spacing: Self.spacing) {
                        SectionTitle(title: sections[index].0, color: model.sectionColor(sections[index].1), model: model)
                        ForEach(section.chats) { chat in
                            ChatRow(chat: chat, model: model)
                        }
                        if section.hidden > 0 {
                            MoreLine(count: section.hidden, model: model)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    if !model.groups.cold.isEmpty {
                        Image(systemName: "snowflake")
                        Text(model.groups.cold.count == 1 ? "1 cold chat" : "\(model.groups.cold.count) cold chats")
                    }
                    Spacer(minLength: 0)
                    if model.stale { ChatsStaleLine(model: model) }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(model.text.opacity(0.35))
                .lineLimit(1)
            }
        }
    }
}

// MARK: Pieces

/// "CLAUDE CODE" and a count of chats in each state, each with its symbol.
struct ChatsHeader: View {
    let model: ChatsModel

    var body: some View {
        let counts: [(ChatBoard.State, Int)] = [
            (.needsYou, model.groups.needsYou.count), (.working, model.groups.working.count),
            (.cached(expires: .distantFuture), model.groups.cached.count), (.cold, model.groups.cold.count),
        ].filter { $0.1 > 0 }

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("CLAUDE CODE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(model.text.opacity(0.45))
            Spacer(minLength: 4)
            ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Image(systemName: ChatsModel.symbol(count.0))
                        .font(.system(size: 9, weight: .bold))
                    Text("\(count.1)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(model.color(count.0))
                .opacity(model.dim)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(model))
    }

    static func summary(_ model: ChatsModel) -> String {
        let g = model.groups
        return ["Claude Code", "\(g.needsYou.count) need you", "\(g.working.count) working",
                "\(g.cached.count) cached", "\(g.cold.count) cold"].joined(separator: ", ")
    }
}

/// One chat: its state symbol, title and folder, what it's doing, and its cache fuse when idle.
struct ChatRow: View {
    let chat: ChatBoard.Chat
    let model: ChatsModel

    var body: some View {
        let state = model.state(chat)
        let color = model.color(state)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: ChatsModel.symbol(state))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(chat.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.text)
                if let folder = chat.folder {
                    Text(folder)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(model.text.opacity(0.4))
                }
                Spacer(minLength: 6)
                Text(model.label(chat, state))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .layoutPriority(1)
            }
            .lineLimit(1)
            if case let .cached(expires) = state {
                CacheFuse(
                    fraction: expires.timeIntervalSince(model.now) / model.board.cacheLifetime,
                    color: color, track: model.text.opacity(0.08)
                )
                .padding(.leading, 20)
            }
        }
        .opacity(model.dim)
        .accessibilityElement(children: .combine)
    }
}

/// How much of a chat's prompt cache lifetime is left, burning down from full to empty.
struct CacheFuse: View {
    let fraction: Double
    let color: Color
    let track: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color)
                    .frame(width: max(2, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

struct SectionTitle: View {
    let title: String
    let color: Color
    let model: ChatsModel

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(color.opacity(0.85))
            .opacity(model.dim)
            .lineLimit(1)
    }
}

struct MoreLine: View {
    let count: Int
    let model: ChatsModel

    var body: some View {
        Text("+\(count) more")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(model.text.opacity(0.35))
            .padding(.leading, 20)
            .lineLimit(1)
    }
}

/// Shown when every open chat has gone cold.
struct QuietLine: View {
    let model: ChatsModel

    var body: some View {
        Text("Nothing working or cached.")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(model.text.opacity(0.45))
            .lineLimit(1)
    }
}

/// "Updated 25 min ago", once PaceBar has stopped writing the board.
struct ChatsStaleLine: View {
    let model: ChatsModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
            Text("Updated \(Format.age(since: model.board.observedAt, now: model.now))")
        }
        .font(.system(size: 10))
        .foregroundStyle(model.text.opacity(0.45))
        .lineLimit(1)
    }
}

struct EmptyChatsView: View {
    let message: String
    let text: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 22))
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(text.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
