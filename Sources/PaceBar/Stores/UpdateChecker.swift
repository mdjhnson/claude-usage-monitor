import Foundation
import Observation
import PaceBarCore

/// Compares this build's version with the latest GitHub release. It checks when Check for Updates
/// is clicked, and once a week only if the person turned that on. It never downloads anything.
@MainActor @Observable
final class UpdateChecker {
    enum Activity: Equatable {
        case idle
        case checking
        /// Only a check someone clicked reports a failure; automatic ones retry quietly.
        case failed(String)
    }

    /// How often a due automatic check is looked for. The check itself runs at most weekly.
    static let pollInterval: TimeInterval = 6 * 3600
    /// Wi-Fi usually takes a few seconds to come back after wake.
    static let wakeDelay: Duration = .seconds(30)

    private(set) var activity = Activity.idle
    /// This build's version, or nil in an unbundled build without one.
    let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let client = UpdateClient()
    @ObservationIgnored private var timer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// The newest release GitHub reported, kept across launches so a found update stays shown
    /// until this build catches up, even when a later check fails.
    var latest: AppVersion? { settings.latestRelease.flatMap(AppVersion.init) }

    var updateAvailable: AppVersion? {
        guard let latest, let current, latest > current else { return nil }
        return latest
    }

    /// Starts or stops automatic checks to match the setting. Called at launch and when it changes.
    func start() {
        if settings.autoCheckUpdates {
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.checkIfDue() }
                }
            }
            checkIfDue()
        } else {
            stop()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func handleWake() {
        guard settings.autoCheckUpdates else { return }
        Task {
            try? await Task.sleep(for: Self.wakeDelay)
            checkIfDue()
        }
    }

    /// Runs an automatic check when they're on and a week has passed since GitHub last answered.
    private func checkIfDue() {
        guard settings.autoCheckUpdates, UpdateCheck.isDue(lastChecked: settings.lastUpdateCheck, now: Date()) else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool = true) {
        guard activity != .checking else { return }
        guard current != nil else {
            if userInitiated { activity = .failed("This build has no version number to compare.") }
            return
        }
        activity = .checking
        Task {
            do throws(UpdateClientError) {
                let version = try await client.latestVersion()
                settings.latestRelease = version.description
                settings.lastUpdateCheck = Date()
                activity = .idle
            } catch {
                // GitHub answered; there's just nothing to compare against yet.
                if error == .noReleases {
                    settings.latestRelease = nil
                    settings.lastUpdateCheck = Date()
                }
                activity = userInitiated ? .failed(Self.message(for: error)) : .idle
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
