import Foundation
import Security

/// The access token lives in the Keychain only: never UserDefaults, never a log line.
struct KeychainStore: TokenStoring {
    private let service: String
    private static let tokenAccount = "oauth-access-token"
    private static let expiryAccount = "oauth-expires-at"

    init(service: String = "dev.anyrouter.app") {
        self.service = service
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

    func save(token: String, expiresAt: Date?) {
        write(Self.tokenAccount, token)
        write(Self.expiryAccount, expiresAt.map { String($0.timeIntervalSince1970) })
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

    private func write(_ account: String, _ value: String?) {
        let query = baseQuery(account)
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }
}
