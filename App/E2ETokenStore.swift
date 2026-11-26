import Foundation

/// UI end-to-end runs against production inject a real API key with the launch argument `-ARTestAPIKey <key>`.
/// The key is held in memory only: an unsigned Simulator build has no Keychain, and nothing should persist it.
/// Compiled into Debug builds only, so a release build cannot read a key from its launch arguments.
#if DEBUG
final class E2ETokenStore: AuthTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(token: String) { value = token }

    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> E2ETokenStore? {
        guard let key = defaults.string(forKey: "ARTestAPIKey"), !key.isEmpty else { return nil }
        return E2ETokenStore(token: key)
    }

    func token() -> String? { lock.withLock { value } }
    func clear() { lock.withLock { value = nil } }
    func expiresAt() -> Date? { nil }

    @discardableResult
    func save(token: String, expiresAt: Date?) -> Bool {
        lock.withLock { value = token }
        return true
    }
}
#endif
