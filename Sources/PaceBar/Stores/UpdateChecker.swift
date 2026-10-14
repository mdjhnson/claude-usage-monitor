import Foundation
import Observation
import PaceBarCore

/// Compares this build's version with the latest GitHub release. It checks when Check for Updates
/// is clicked, and once a week only if the person turned that on. It never downloads anything.
@MainActor @Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppVersion)
        case failed(String)
    }

    /// How often a due automatic check is looked for. The check itself runs at most weekly.
    static let pollInterval: TimeInterval = 6 * 3600

    private(set) var state = State.idle
    /// This build's version, or nil in an unbundled build without one.
    let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let client = UpdateClient()
    @ObservationIgnored private var timer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Set after any check that found a newer release, including an automatic one.
    var updateAvailable: AppVersion? {
        if case .available(let version) = state { version } else { nil }
    }

    func start() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Runs an automatic check when they're on and a week has passed. Also called on wake and
    /// when the setting is turned on.
    func checkIfDue() {
        guard settings.autoCheckUpdates, UpdateCheck.isDue(lastChecked: settings.lastUpdateCheck, now: Date()) else { return }
        check()
    }

    func check() {
        guard state != .checking else { return }
        guard let current else {
            state = .failed("This build has no version number to compare.")
            return
        }
        state = .checking
        Task {
            do throws(UpdateClientError) {
                let latest = try await client.latestVersion()
                settings.lastUpdateCheck = Date()
                state = latest > current ? .available(latest) : .upToDate
            } catch {
                // GitHub answered; there's just nothing to compare against yet.
                if error == .noReleases { settings.lastUpdateCheck = Date() }
                state = .failed(Self.message(for: error))
            }
        }
    }

    static func message(for error: UpdateClientError) -> String {
        switch error {
        case .noReleases: "No releases have been published yet."
        case .rateLimited: "GitHub is limiting requests right now. Try again in an hour."
        case .network: "Couldn't reach GitHub. Check your connection and try again."
        case .decoding: "Couldn't read the latest release's version."
        case .http(let status): "GitHub returned an error (\(status))."
        case .redirectRefused, .hostNotAllowed: "GitHub sent an unexpected response, so PaceBar stopped."
        }
    }
}
