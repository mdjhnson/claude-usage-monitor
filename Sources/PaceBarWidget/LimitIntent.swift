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

/// One limit, identified by `WindowKind.id` ("session", "weekly", "weekly.sonnet").
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
}

/// Offers the 5-hour session and weekly limit always, plus any per-model weekly limits in the
/// latest snapshot.
struct LimitQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LimitEntity] {
        let known = Self.available()
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
