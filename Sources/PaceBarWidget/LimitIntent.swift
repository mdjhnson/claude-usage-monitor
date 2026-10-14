import AppIntents
import WidgetKit
import PaceBarCore

/// The small widget's setting: which limit it shows.
struct LimitWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Limit" }
    static var description: IntentDescription { "Choose which limit the widget shows." }

    @Parameter(title: "Limit")
    var limit: LimitEntity?

    init() {}
}

/// The medium widget's setting: which graph it shows beside the bars.
struct GraphWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Graph" }
    static var description: IntentDescription { "Choose which usage graph the widget shows." }

    @Parameter(title: "Graph", optionsProvider: GraphOptions())
    var graph: LimitEntity?

    init() {}
}

/// Every limit, plus the session and weekly graphs together.
struct GraphOptions: DynamicOptionsProvider {
    func results() async throws -> [LimitEntity] {
        LimitQuery.available() + [.both]
    }

    func defaultResult() async -> LimitEntity? {
        LimitEntity(kind: .session)
    }
}

/// One limit, identified by `WindowKind.id` ("session", "weekly", "weekly.sonnet"). The medium
/// widget's graph setting also has `both`.
struct LimitEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Limit" }
    static var defaultQuery: LimitQuery { LimitQuery() }

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(kind: WindowKind) {
        id = kind.id
        title = kind.title
    }

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    static let bothID = "session+weekly"
    static var both: LimitEntity { LimitEntity(id: bothID, title: "5-Hour Session and Weekly") }
}

/// Offers the 5-hour session and weekly limit always, plus any per-model weekly limits in the
/// latest snapshot.
struct LimitQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LimitEntity] {
        let known = Self.available() + [.both]
        // A limit the API stopped reporting keeps its setting; the widget falls back meanwhile.
        return identifiers.map { id in known.first { $0.id == id } ?? LimitEntity(id: id, title: id) }
    }

    func suggestedEntities() async throws -> [LimitEntity] {
        Self.available()
    }

    func defaultResult() async -> LimitEntity? {
        LimitEntity(kind: .session)
    }

    static func available() -> [LimitEntity] {
        var kinds: [WindowKind] = [.session, .weekly]
        for kind in WidgetSnapshotStore()?.read()?.windows.map(\.kind) ?? [] where !kinds.contains(kind) {
            kinds.append(kind)
        }
        return kinds.map(LimitEntity.init(kind:))
    }
}
