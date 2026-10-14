import Foundation

/// What the widgets show. The app writes it to the App Group container after each refresh and
/// the widget extension reads it, since the sandboxed extension can't read the Keychain.
///
/// Usage values, this cycle's readings and display settings only. It must never hold a
/// credential, a response body or anything else from the Keychain.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public let kind: WindowKind
        public let utilization: Double
        public let resetsAt: Date?
        /// This cycle's readings, downsampled to at most `WidgetSnapshot.maxSamples`.
        public let samples: [UsageSample]

        public init(kind: WindowKind, utilization: Double, resetsAt: Date?, samples: [UsageSample]) {
            self.kind = kind
            self.utilization = utilization
            self.resetsAt = resetsAt
            self.samples = samples
        }

        public var usageWindow: UsageWindow {
            UsageWindow(kind: kind, bucket: UsageBucket(utilization: utilization, resetsAt: resetsAt))
        }
    }

    /// The settings the widget needs to draw what the popover draws.
    public struct Display: Codable, Equatable, Sendable {
        public let margin: Double
        public let schedule: WorkSchedule
        /// `ColorMode.rawValue`.
        public let colorMode: String
        public let warningAt: Double
        public let criticalAt: Double
        public let usageGraph: Bool
        /// `WeeklyDayMarkers.rawValue`.
        public let weeklyDayMarkers: String
        /// The theme in use as `0xRRGGBB` by token name. `background` is the popover's actual
        /// background, so preset blending and custom colors arrive already resolved.
        public let theme: [String: UInt32]

        public init(
            margin: Double, schedule: WorkSchedule, colorMode: String, warningAt: Double, criticalAt: Double,
            usageGraph: Bool, weeklyDayMarkers: String, theme: [String: UInt32]
        ) {
            self.margin = margin
            self.schedule = schedule
            self.colorMode = colorMode
            self.warningAt = warningAt
            self.criticalAt = criticalAt
            self.usageGraph = usageGraph
            self.weeklyDayMarkers = weeklyDayMarkers
            self.theme = theme
        }
    }

    /// Readings kept per window. Enough for the graph's shape at widget size.
    public static let maxSamples = 120

    public let fetchedAt: Date
    public let refreshInterval: TimeInterval
    /// True while the last refresh failed. Only that fact, never the error itself.
    public let hasError: Bool
    /// The windows shown in the popover, in display order.
    public let windows: [Window]
    public let display: Display

    public init(fetchedAt: Date, refreshInterval: TimeInterval, hasError: Bool, windows: [Window], display: Display) {
        self.fetchedAt = fetchedAt
        self.refreshInterval = refreshInterval
        self.hasError = hasError
        self.windows = windows
        self.display = display
    }

    /// Matches the popover: stale after a failed refresh or two missed refreshes. Widgets update
    /// less often than the popover, so the age allowance is never under 10 minutes.
    public func isStale(now: Date) -> Bool {
        hasError || now.timeIntervalSince(fetchedAt) > max(2 * refreshInterval, 600)
    }

    /// Pacing at `now`, recomputed so the zone stays right as time passes without new data.
    public func pacing(for window: Window, now: Date, calendar: Calendar = .current) -> PacingResult? {
        guard let resetsAt = window.resetsAt else { return nil }
        return PacingCalculator.calculate(
            utilization: window.utilization, resetsAt: resetsAt, kind: window.kind,
            margin: display.margin, schedule: display.schedule, now: now, calendar: calendar
        )
    }

    /// The steady-pace line for a window's graph, or nil without a reset time.
    public func paceCurve(for window: Window, calendar: Calendar = .current) -> [GraphPoint]? {
        guard let resetsAt = window.resetsAt else { return nil }
        return PacingCalculator.paceCurve(resetsAt: resetsAt, kind: window.kind, schedule: display.schedule, calendar: calendar)
    }
}

/// Reads and writes `snapshot.json` in the App Group container shared with the widget.
/// This is the only file PaceBar writes.
public struct WidgetSnapshotStore: Sendable {
    /// Info.plist key holding the App Group ID. The build fills in the team prefix.
    public static let groupKey = "PaceBarAppGroup"
    public static let fileName = "snapshot.json"

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The shared container's file, or nil when the bundle has no usable App Group.
    public init?(bundle: Bundle = .main) {
        guard let group = Self.group(bundle: bundle),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        self.init(fileURL: container.appendingPathComponent(Self.fileName))
    }

    /// The Darwin notification a widget's refresh button posts and the app listens for. It
    /// carries no data; the app treats it like opening the popover.
    public static func refreshNotificationName(bundle: Bundle = .main) -> String? {
        group(bundle: bundle).map { $0 + ".refresh" }
    }

    private static func group(bundle: Bundle) -> String? {
        guard let group = bundle.object(forInfoDictionaryKey: groupKey) as? String,
              !group.isEmpty, !group.hasPrefix(".") else { return nil }
        return group
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    /// Nil when there's no file yet or it can't be decoded (for example, from another version).
    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
