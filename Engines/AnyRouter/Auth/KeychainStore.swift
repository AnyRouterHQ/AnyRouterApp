import Foundation
import Security

/// What `AnyRouterAuth` needs from the token store. Tests and the launch-path spies use a fake.
protocol AuthTokenStore: TokenStoring {
    func expiresAt() -> Date?
    @discardableResult func save(token: String, expiresAt: Date?) -> Bool
}

/// The access token lives in the Keychain only: never UserDefaults, never a log line.
struct KeychainStore: AuthTokenStore {
    private let service: String
    private let add: @Sendable (CFDictionary) -> OSStatus
    private static let tokenAccount = "oauth-access-token"
    private static let expiryAccount = "oauth-expires-at"

    /// `add` is the Keychain insert; tests pass one that fails.
    init(service: String = "dev.anyrouter.app", add: @escaping @Sendable (CFDictionary) -> OSStatus = { SecItemAdd($0, nil) }) {
        self.service = service
        self.add = add
    }

    /// The token, or `nil` when none is stored or it has expired.
    func token() -> String? {
        if let expiry = expiresAt(), expiry <= Date() { return nil }
        guard let value = read(Self.tokenAccount), !value.isEmpty else { return nil }
        return value
    }

    func expiresAt() -> Date? {
        guard let text = read(Self.expiryAccount), let seconds = TimeInterval(text) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Returns false when the Keychain refused the token, so the caller does not report a sign-in that did not stick.
    @discardableResult
    func save(token: String, expiresAt: Date?) -> Bool {
        let stored = write(Self.tokenAccount, token)
        write(Self.expiryAccount, expiresAt.map { String($0.timeIntervalSince1970) })
        return stored
    }

    func clear() {
        write(Self.tokenAccount, nil)
        write(Self.expiryAccount, nil)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the item. `nil` deletes it. Returns whether the Keychain accepted the change.
    @discardableResult
    private func write(_ account: String, _ value: String?) -> Bool {
        let query = baseQuery(account)
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return true }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return add(insert as CFDictionary) == errSecSuccess
    }
}
