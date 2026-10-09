import Foundation

/// One usage limit: percent used and when it resets.
public struct UsageBucket: Equatable, Sendable {
    /// 0 to 100 (can exceed 100 when over the limit).
    public let utilization: Double
    /// Nil when the API reports no reset time.
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct UsageWindow: Equatable, Sendable, Identifiable {
    public let kind: WindowKind
    public let bucket: UsageBucket
    public var id: String { kind.id }
}

/// Tolerant decode of `GET /api/oauth/usage`.
///
/// Unknown keys are ignored, a malformed bucket becomes nil, and malformed `limits[]`
/// entries are skipped individually. Only a non-object top level fails the decode.
public struct UsageResponse: Decodable, Equatable, Sendable {
    public let fiveHour: UsageBucket?
    public let sevenDay: UsageBucket?
    /// Per-model weekly buckets keyed by lowercase model name.
    public let modelWeekly: [String: (name: String, bucket: UsageBucket)]

    /// Flat per-model keys and the display name each one maps to.
    static let flatModelKeys: [(key: String, name: String)] = [
        ("seven_day_sonnet", "Sonnet"),
        ("seven_day_opus", "Opus"),
        ("seven_day_fable", "Fable"),
    ]

    public init(fiveHour: UsageBucket?, sevenDay: UsageBucket?, modelWeekly: [String: (name: String, bucket: UsageBucket)] = [:]) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.modelWeekly = modelWeekly
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)

        func flat(_ key: String) -> UsageBucket? {
            (try? container.decodeIfPresent(RawBucket.self, forKey: AnyKey(key)))??.bucket
        }

        let limits = ((try? container.decodeIfPresent([Lossy<LimitEntry>].self, forKey: AnyKey("limits"))) ?? nil)?
            .compactMap(\.value) ?? []

        fiveHour = Self.prefer(flat("five_hour"), limits.first { $0.kind == "session" }?.bucket)
        sevenDay = Self.prefer(flat("seven_day"), limits.first { $0.kind == "weekly_all" }?.bucket)

        var models: [String: (name: String, bucket: UsageBucket)] = [:]
        for entry in limits where entry.kind == "weekly_scoped" {
            guard let name = entry.modelName, let bucket = entry.bucket else { continue }
            let key = name.lowercased()
            if models[key] == nil { models[key] = (name, bucket) }
        }
        for (key, name) in Self.flatModelKeys {
            guard let bucket = flat(key) else { continue }
            let id = name.lowercased()
            let fallback = models[id]
            if let chosen = Self.prefer(bucket, fallback?.bucket) {
                models[id] = (fallback?.name ?? name, chosen)
            }
        }
        modelWeekly = models
    }

    /// The flat key wins when it carries a reset time; otherwise a `limits[]` entry that
    /// does is used; otherwise whichever exists.
    static func prefer(_ flat: UsageBucket?, _ fallback: UsageBucket?) -> UsageBucket? {
        if let flat, flat.resetsAt != nil { return flat }
        if let fallback, fallback.resetsAt != nil { return fallback }
        return flat ?? fallback
    }

    /// Windows in display order: session, weekly, then per-model weekly by name.
    public var windows: [UsageWindow] {
        var out: [UsageWindow] = []
        if let fiveHour { out.append(UsageWindow(kind: .session, bucket: fiveHour)) }
        if let sevenDay { out.append(UsageWindow(kind: .weekly, bucket: sevenDay)) }
        for (_, model) in modelWeekly.sorted(by: { $0.key < $1.key }) {
            out.append(UsageWindow(kind: .weeklyModel(model.name), bucket: model.bucket))
        }
        return out
    }

    public static func == (lhs: UsageResponse, rhs: UsageResponse) -> Bool {
        lhs.windows == rhs.windows
    }
}

// MARK: - Decoding helpers

struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Decodes `T` or swallows the error, so one bad array element never sinks the rest.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// `{ "utilization": Double, "resets_at": String? }`
struct RawBucket: Decodable {
    let bucket: UsageBucket

    enum CodingKeys: String, CodingKey { case utilization, resetsAt = "resets_at" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let utilization = try c.decode(Double.self, forKey: .utilization)
        guard utilization.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .utilization, in: c, debugDescription: "non-finite")
        }
        let raw = try? c.decodeIfPresent(String.self, forKey: .resetsAt)
        bucket = UsageBucket(utilization: utilization, resetsAt: raw.flatMap { ISO8601.parse($0) })
    }
}

/// An entry of the `limits[]` array on migrated accounts. Uses `percent`, not `utilization`.
struct LimitEntry: Decodable {
    let kind: String?
    let percent: Double?
    let resetsAt: String?
    let modelName: String?

    enum CodingKeys: String, CodingKey { case kind, percent, utilization, resetsAt = "resets_at", scope }
    enum ScopeKeys: String, CodingKey { case model }
    enum ModelKeys: String, CodingKey { case displayName = "display_name" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        let fromPercent: Double? = (try? c.decodeIfPresent(Double.self, forKey: .percent)) ?? nil
        let fromUtilization: Double? = (try? c.decodeIfPresent(Double.self, forKey: .utilization)) ?? nil
        percent = fromPercent ?? fromUtilization
        resetsAt = (try? c.decodeIfPresent(String.self, forKey: .resetsAt)) ?? nil
        let scope = try? c.nestedContainer(keyedBy: ScopeKeys.self, forKey: .scope)
        let model = try? scope?.nestedContainer(keyedBy: ModelKeys.self, forKey: .model)
        let name = (try? model?.decodeIfPresent(String.self, forKey: .displayName)) ?? nil
        modelName = name.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }

    var bucket: UsageBucket? {
        guard let percent, percent.isFinite else { return nil }
        return UsageBucket(utilization: percent, resetsAt: resetsAt.flatMap { ISO8601.parse($0) })
    }
}

/// ISO 8601 parsing that accepts any number of fractional-second digits (the API sends 6).
public enum ISO8601 {
    public static func parse(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)
        guard let tIndex = s.firstIndex(of: "T") else { return nil }

        var base = s
        var fraction: Double = 0
        if let dot = s[tIndex...].firstIndex(of: ".") {
            let digitsEnd = s[s.index(after: dot)...].firstIndex { !$0.isASCII || !$0.isNumber } ?? s.endIndex
            let digits = s[s.index(after: dot)..<digitsEnd]
            guard !digits.isEmpty, let value = Double("0." + digits) else { return nil }
            fraction = value
            base = String(s[..<dot]) + String(s[digitsEnd...])
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: base)?.addingTimeInterval(fraction)
    }
}
