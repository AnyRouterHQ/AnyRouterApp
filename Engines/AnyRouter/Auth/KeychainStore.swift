import Foundation
import Security

/// What `AnyRouterAuth` needs from the token store. Tests and the launch-path spies use a fake.
protocol AuthTokenStore: TokenStoring {
    func expiresAt() -> Date?
    @discardableResult func save(token: String, expiresAt: Date?) -> Bool
}

/// Where the token is kept. The system Keychain in the app. Tests use memory: an unsigned Simulator build has no Keychain access.
protocol SecretBacking: Sendable {
    func read(_ account: String) -> String?
    /// Replaces the item. `nil` deletes it. Returns whether the change was accepted.
    func write(_ account: String, _ value: String?) -> Bool
}

struct SystemKeychain: SecretBacking {
    let service: String

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return Self.string(from: item)
    }

    static func string(from item: CFTypeRef?) -> String? {
        (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    func write(_ account: String, _ value: String?) -> Bool {
        let query = baseQuery(account)
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return true }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
}

/// The access token lives in the Keychain only: never UserDefaults, never a log line.
struct KeychainStore: AuthTokenStore {
    private let backing: any SecretBacking
    private static let tokenAccount = "oauth-access-token"
    private static let expiryAccount = "oauth-expires-at"

    init(service: String = "dev.anyrouter.app") {
        backing = SystemKeychain(service: service)
    }

    init(backing: any SecretBacking) {
        self.backing = backing
    }

    /// The token, or `nil` when none is stored or it has expired.
    func token() -> String? {
        if let expiry = expiresAt(), expiry <= Date() { return nil }
        guard let value = backing.read(Self.tokenAccount), !value.isEmpty else { return nil }
        return value
    }

    func expiresAt() -> Date? {
        guard let text = backing.read(Self.expiryAccount), let seconds = TimeInterval(text) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Returns false when the Keychain refused the token, so the caller does not report a sign-in that did not stick.
    @discardableResult
    func save(token: String, expiresAt: Date?) -> Bool {
        let stored = backing.write(Self.tokenAccount, token)
        _ = backing.write(Self.expiryAccount, expiresAt.map { String($0.timeIntervalSince1970) })
        return stored
    }

    func clear() {
        _ = backing.write(Self.tokenAccount, nil)
        _ = backing.write(Self.expiryAccount, nil)
    }
}
