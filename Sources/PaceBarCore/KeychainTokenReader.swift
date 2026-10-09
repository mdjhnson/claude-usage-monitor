import Foundation
import Security
import os

public enum KeychainReadError: Error, Equatable, Sendable {
    /// `security` exit 44, or no item under the service.
    case notFound
    /// `security` exit 45: the user denied access.
    case accessDenied
    /// The child did not finish in time and was killed.
    case timedOut
    /// `/usr/bin/security` could not be launched.
    case launchFailed
    /// Items exist, but none carries a usable `claudeAiOauth.accessToken`.
    case unusablePayload
    case unexpectedExit(Int32)
}

/// Reads Claude Code's OAuth token from the login Keychain. Read-only, always.
///
/// Accounts are enumerated with `SecItemCopyMatching` asking for attributes only (never
/// `kSecReturnData`, which would prompt for this app). Each account's payload is then read
/// with `/usr/bin/security find-generic-password -s <service> -a <account> -w`: an absolute
/// path, fixed arguments, no shell, and a minimal environment. This is the app's only
/// subprocess.
public struct KeychainTokenReader: Sendable {
    public static let service = "Claude Code-credentials"
    static let securityURL = URL(fileURLWithPath: "/usr/bin/security")
    static let maxAccounts = 8

    /// Background refreshes: the brief's 3 second limit.
    public static let backgroundTimeout: TimeInterval = 3
    /// User-initiated reads (first launch, Retry): long enough to answer the macOS prompt.
    public static let interactiveTimeout: TimeInterval = 60

    let service: String
    private static let log = Logger(subsystem: "io.github.mdjhnson.pacebar", category: "keychain")

    public init() { self.service = Self.service }

    /// Test hook: point at a service name that does not exist.
    init(service: String) { self.service = service }

    /// Number of items under the service, from attributes only. Nil if the query failed.
    public func itemCount() -> Int? {
        let (accounts, status) = enumerateAccounts()
        if status == errSecItemNotFound { return 0 }
        return status == errSecSuccess ? accounts.count : nil
    }

    /// Reads every candidate item and returns the credential with the latest expiry.
    public func read(timeout: TimeInterval) async -> Result<OAuthCredential, KeychainReadError> {
        let service = self.service
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.readSync(service: service, timeout: timeout))
            }
        }
    }

    // MARK: - Implementation

    static func readSync(service: String, timeout: TimeInterval) -> Result<OAuthCredential, KeychainReadError> {
        let (accounts, status) = enumerateAccounts(service: service)
        if status == errSecItemNotFound { return .failure(.notFound) }

        // If attribute enumeration failed for another reason, let `security` pick the item.
        let targets: [String?] = accounts.isEmpty ? [nil] : Array(accounts.prefix(maxAccounts)).map { $0 }

        var credentials: [OAuthCredential] = []
        var errors: [KeychainReadError] = []
        for account in targets {
            switch runSecurity(service: service, account: account, timeout: timeout) {
            case .success(let data):
                if let credential = CredentialParser.parse(data) {
                    credentials.append(credential)
                } else {
                    errors.append(.unusablePayload)
                }
            case .failure(let error):
                errors.append(error)
            }
            // A hang usually affects every call; don't stack timeouts.
            if errors.last == .timedOut { break }
        }

        if let best = CredentialParser.best(of: credentials) { return .success(best) }
        log.error("keychain read failed: \(String(describing: errors), privacy: .private)")
        return .failure(mostRelevant(errors))
    }

    /// The error a user can act on first.
    static func mostRelevant(_ errors: [KeychainReadError]) -> KeychainReadError {
        let priority: [KeychainReadError] = [.accessDenied, .timedOut, .launchFailed, .unusablePayload]
        for candidate in priority where errors.contains(candidate) { return candidate }
        if let other = errors.first(where: { if case .unexpectedExit = $0 { true } else { false } }) { return other }
        return .notFound
    }

    func enumerateAccounts() -> ([String], OSStatus) { Self.enumerateAccounts(service: service) }

    static func enumerateAccounts(service: String) -> ([String], OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return ([], status) }
        var seen = Set<String>()
        let accounts = items.compactMap { $0[kSecAttrAccount as String] as? String }.filter { seen.insert($0).inserted }
        return (accounts, status)
    }

    /// Runs `/usr/bin/security` once. Stdout is drained concurrently so a full pipe can never
    /// stall the child; on timeout the child gets SIGTERM, then SIGKILL, and is reaped.
    static func runSecurity(service: String, account: String?, timeout: TimeInterval) -> Result<Data, KeychainReadError> {
        var arguments = ["find-generic-password", "-s", service]
        if let account { arguments += ["-a", account] }
        arguments.append("-w")

        let process = Process()
        process.executableURL = securityURL
        process.arguments = arguments
        process.environment = minimalEnvironment()
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return .failure(.launchFailed)
        }
        try? stdout.fileHandleForWriting.close()

        let output = OutputCollector()
        let reader = stdout.fileHandleForReading
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            output.set(reader.readDataToEndOfFile())
            drained.signal()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            _ = drained.wait(timeout: .now() + 1)
            output.clear()
            return .failure(.timedOut)
        }
        // The child has exited, so EOF is imminent; a drain that still hasn't finished fails closed.
        if drained.wait(timeout: .now() + 5) == .timedOut {
            output.clear()
            return .failure(.timedOut)
        }

        switch process.terminationStatus {
        case 0:
            return .success(output.take())
        case 44:
            return .failure(.notFound)
        case 45:
            return .failure(.accessDenied)
        case let code:
            output.clear()
            return .failure(.unexpectedExit(code))
        }
    }

    /// Only `HOME`, from the password database rather than the inherited environment.
    static func minimalEnvironment() -> [String: String] {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return [:] }
        return ["HOME": String(cString: dir)]
    }
}

/// Holds subprocess output across threads. Once taken or cleared it is closed: output that
/// arrives later is zeroed instead of being kept.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var closed = false

    func set(_ new: consuming Data) {
        var incoming = new
        lock.withLock {
            if closed {
                incoming.resetBytes(in: 0..<incoming.count)
            } else {
                data = incoming
            }
        }
    }

    func take() -> Data {
        lock.withLock {
            closed = true
            defer { data = Data() }
            return data
        }
    }

    func clear() {
        lock.withLock {
            closed = true
            data.resetBytes(in: 0..<data.count)
            data = Data()
        }
    }
}
