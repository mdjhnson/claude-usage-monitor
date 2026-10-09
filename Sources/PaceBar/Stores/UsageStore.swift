import Foundation
import Observation
import PaceBarCore

struct UsageSnapshot: Equatable {
    let usage: UsageResponse
    let fetchedAt: Date
}

enum StoreError: Equatable {
    case keychain(KeychainReadError)
    /// The Keychain token's own expiry has passed; no request was sent.
    case expiredLogin
    case client(UsageClientError)

    /// Auth problems are shown in red; transient ones in orange.
    var isAuthProblem: Bool {
        switch self {
        case .keychain, .expiredLogin: true
        case .client(.tokenExpired): true
        case .client: false
        }
    }

    /// Short name for the diagnostic report.
    var kind: String {
        switch self {
        case .keychain(let e): "keychain.\(e)"
        case .expiredLogin: "expiredLogin"
        case .client(let e): "client.\(e)"
        }
    }

    func message(retryAt: Date?) -> String {
        switch self {
        case .keychain(.notFound):
            "Sign in to Claude Code first (run `claude`, then `/login`)."
        case .keychain(.accessDenied):
            "Keychain access was denied. Click Retry, then choose “Always Allow” when macOS asks."
        case .keychain(.timedOut):
            "The Keychain didn't answer in time. Click Retry and answer the macOS prompt if one appears."
        case .keychain(.launchFailed):
            "Couldn't run /usr/bin/security to read the Claude Code login."
        case .keychain(.unusablePayload):
            "Claude Code's Keychain item has no login token. Sign in again with `/login`."
        case .keychain(.unexpectedExit(let code)):
            "Reading the Claude Code login failed (security exit \(code))."
        case .expiredLogin, .client(.tokenExpired):
            "Your Claude Code login has expired. Open Claude Code so it can refresh its login."
        case .client(.rateLimited):
            if let retryAt {
                "Rate limited by Anthropic. Retrying at \(retryAt.formatted(date: .omitted, time: .shortened))."
            } else {
                "Rate limited by Anthropic. Retrying later."
            }
        case .client(.http(let status)):
            "Anthropic returned an error (HTTP \(status))."
        case .client(.redirectRefused(let status)):
            "Refused an unexpected redirect (HTTP \(status))."
        case .client(.hostNotAllowed):
            "Blocked a request to an unexpected host."
        case .client(.network):
            "Can't reach api.anthropic.com."
        case .client(.decoding):
            "Unexpected response from Anthropic. Use Copy diagnostic in Settings to report it."
        }
    }
}

/// Owns polling, backoff and the last good data. Everything lives in memory only.
@MainActor @Observable
final class UsageStore {
    private(set) var snapshot: UsageSnapshot?
    private(set) var lastError: StoreError?
    private(set) var isRefreshing = false
    /// Set while a 429 backoff is in force.
    private(set) var retryNotBefore: Date?

    // Diagnostic facts. Never the token itself.
    private(set) var tokenPresent = false
    private(set) var tokenExpiresAt: Date?
    private(set) var lastHTTPStatus: Int?
    private(set) var lastResponseShape: String?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let reader = KeychainTokenReader()
    @ObservationIgnored private let client = UsageClient()
    @ObservationIgnored private var backoff = BackoffPolicy()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastPopoverRefresh: Date?
    /// The first Keychain read after launch may show a macOS prompt, so it gets the long timeout.
    @ObservationIgnored private var nextReadIsInteractive = true
    /// After an explicit denial, background polls stop asking until the user clicks Retry.
    @ObservationIgnored private var keychainPaused = false

    static let popoverDebounce: TimeInterval = 30

    static let wakeDelay: TimeInterval = 10

    init(settings: SettingsStore) {
        self.settings = settings
        observeRefreshInterval()
    }

    /// Applies a new refresh interval wherever it was changed from.
    private func observeRefreshInterval() {
        withObservationTracking {
            _ = settings.refreshInterval
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reschedule()
                self?.observeRefreshInterval()
            }
        }
    }

    /// Data is stale when the last attempt failed or it is older than two poll intervals.
    func isStale(now: Date) -> Bool {
        guard let snapshot else { return false }
        return lastError != nil || now.timeIntervalSince(snapshot.fetchedAt) > 2 * settings.refreshInterval
    }

    func isBackingOff(now: Date) -> Bool {
        guard let retryNotBefore else { return false }
        return now < retryNotBefore
    }

    // MARK: Lifecycle

    /// - Parameter initialDelay: wait before the first refresh (used on wake, so Wi-Fi can reconnect).
    func start(refreshImmediately: Bool = true, initialDelay: TimeInterval = 0) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            if initialDelay > 0 {
                do { try await Task.sleep(for: .seconds(initialDelay)) } catch { return }
            }
            var refreshNow = refreshImmediately
            while !Task.isCancelled {
                guard let self else { return }
                if refreshNow { await self.refresh(userInitiated: false) }
                refreshNow = true
                let delay = self.nextDelay(now: Date())
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Apply a new refresh interval without an extra request. A refresh in flight is left alone:
    /// the loop reads the interval again as soon as it finishes.
    func reschedule() {
        guard pollTask != nil, !isRefreshing else { return }
        start(refreshImmediately: false)
    }

    func handleSleep() { stop() }

    /// Refresh shortly after wake (not instantly: Wi-Fi is usually still reconnecting), unless a
    /// rate-limit backoff is still running.
    func handleWake() {
        if isBackingOff(now: Date()) {
            start(refreshImmediately: false)
        } else {
            start(refreshImmediately: true, initialDelay: Self.wakeDelay)
        }
    }

    func popoverOpened() {
        let now = Date()
        if let last = lastPopoverRefresh, now.timeIntervalSince(last) < Self.popoverDebounce { return }
        if let fetched = snapshot?.fetchedAt, now.timeIntervalSince(fetched) < Self.popoverDebounce, lastError == nil { return }
        lastPopoverRefresh = now
        Task { await refresh(userInitiated: false) }
    }

    /// The Retry and refresh buttons. Uses the long Keychain timeout so a prompt can be answered.
    func retry() {
        keychainPaused = false
        nextReadIsInteractive = true
        Task { await refresh(userInitiated: true) }
    }

    private func nextDelay(now: Date) -> TimeInterval {
        let interval = min(max(settings.refreshInterval, SettingsStore.refreshRange.lowerBound), SettingsStore.refreshRange.upperBound)
        if let retryNotBefore, retryNotBefore > now {
            return max(retryNotBefore.timeIntervalSince(now), 1)
        }
        return interval
    }

    // MARK: Refresh

    func refresh(userInitiated: Bool) async {
        guard !isRefreshing else { return }
        let now = Date()
        if isBackingOff(now: now) { return }
        if keychainPaused && !userInitiated { return }

        isRefreshing = true
        defer { isRefreshing = false }

        let timeout = (userInitiated || nextReadIsInteractive)
            ? KeychainTokenReader.interactiveTimeout
            : KeychainTokenReader.backgroundTimeout
        nextReadIsInteractive = false

        // The token is re-read every cycle and lives only in this scope.
        let credential: OAuthCredential
        switch await reader.read(timeout: timeout) {
        case .failure(let error):
            tokenPresent = false
            tokenExpiresAt = nil
            lastError = .keychain(error)
            if error == .accessDenied { keychainPaused = true }
            return
        case .success(let c):
            credential = c
        }

        tokenPresent = true
        tokenExpiresAt = credential.expiresAt
        if credential.isExpired(now: Date()) {
            lastError = .expiredLogin
            return
        }

        do {
            let result = try await client.fetchUsage(credential: credential)
            snapshot = UsageSnapshot(usage: result.usage, fetchedAt: Date())
            lastResponseShape = result.shape
            lastHTTPStatus = 200
            lastError = nil
            backoff.recordSuccess()
            retryNotBefore = nil
        } catch {
            // Cancelled because polling was restarted or the Mac is going to sleep: not an error.
            if case .network(let code) = error, code == URLError.Code.cancelled.rawValue { return }
            lastError = .client(error)
            switch error {
            case .rateLimited(let retryAfter):
                lastHTTPStatus = 429
                let delay = backoff.recordRateLimit(retryAfter: retryAfter, baseInterval: settings.refreshInterval)
                retryNotBefore = Date().addingTimeInterval(delay)
            case .tokenExpired(let status), .http(let status), .redirectRefused(let status):
                lastHTTPStatus = status
            case .hostNotAllowed, .network, .decoding:
                break
            }
        }
    }

    // MARK: Diagnostic

    func diagnosticReport() async -> DiagnosticReport {
        let reader = self.reader
        let itemCount = await Task.detached { reader.itemCount() }.value
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "0"))"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return DiagnosticReport(
            appVersion: version,
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            keychainItemCount: itemCount,
            tokenPresent: tokenPresent,
            tokenExpiresIn: tokenExpiresAt.map { $0.timeIntervalSinceNow },
            lastHTTPStatus: lastHTTPStatus,
            lastErrorKind: lastError?.kind,
            refreshInterval: settings.refreshInterval,
            backoffActive: isBackingOff(now: Date()),
            responseShape: lastResponseShape
        )
    }
}
