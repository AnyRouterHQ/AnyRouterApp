import Foundation
import Security

/// Bearer tokens for custom MCP servers. Keychain only: never UserDefaults, never a log line.
protocol MCPCredentialStoring: Sendable {
    func token(for serverID: String) -> String?
    /// False when the token could not be stored (for example a locked or full Keychain).
    func save(token: String, for serverID: String) -> Bool
    func remove(for serverID: String)
}

struct MCPKeychainCredentialStore: MCPCredentialStoring {
    private let service: String

    init(service: String = "oneni.anyr.app.mcp") {
        self.service = service
    }

    func token(for serverID: String) -> String? {
        var query = baseQuery(serverID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { return nil }
        return value
    }

    func save(token: String, for serverID: String) -> Bool {
        remove(for: serverID)
        var insert = baseQuery(serverID)
        insert[kSecValueData as String] = Data(token.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    func remove(for serverID: String) {
        SecItemDelete(baseQuery(serverID) as CFDictionary)
    }

    private func baseQuery(_ serverID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "mcp-token-\(serverID)",
        ]
    }
}
