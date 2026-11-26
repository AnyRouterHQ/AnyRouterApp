import Foundation

enum IntegrationsLogic {
    enum URLProblem: LocalizedError, Equatable {
        case empty
        case notHTTPS
        case invalid
        case duplicate
        /// Not a URL problem, but it ends the same "could not add this server" path.
        case keychain

        var errorDescription: String? {
            switch self {
            case .empty: return "Enter the server URL."
            case .notHTTPS: return "Use an https:// URL. Plain http is only allowed for localhost."
            case .invalid: return "That is not a valid server URL."
            case .duplicate: return "This server is already added."
            case .keychain: return "The token could not be saved in the Keychain. The server was not added."
            }
        }
    }

    /// Accepts `https://host/path` (and `http://` only for localhost). Adds `https://` when the scheme is missing.
    static func validate(_ input: String) -> Result<URL, URLProblem> {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let host = url.host(), !host.isEmpty,
            let scheme = url.scheme?.lowercased()
        else { return .failure(.invalid) }
        switch scheme {
        case "https": return .success(url)
        case "http":
            let local = host == "localhost" || host == "127.0.0.1" || host == "::1"
            return local ? .success(url) : .failure(.notHTTPS)
        default: return .failure(.invalid)
        }
    }

    /// Name suggested from the host, `mcp.example.com` becomes `example.com`.
    static func defaultName(for url: URL) -> String {
        let host = url.host() ?? "Server"
        for prefix in ["mcp.", "www."] where host.hasPrefix(prefix) && host.count > prefix.count + 2 {
            return String(host.dropFirst(prefix.count))
        }
        return host
    }

    /// One line for a server row: "Connected · 3 tools", "Sign in to connect", or the error text.
    static func statusText(_ status: IntegrationsStore.Status, toolCount: Int) -> String {
        switch status {
        case .idle: return "Not connected"
        case .connecting: return "Connecting"
        case .needsSignIn: return "Sign in to connect"
        case .connected: return "Connected · \(toolCount == 1 ? "1 tool" : "\(toolCount) tools")"
        case .failed(let message): return message
        }
    }

    /// Key of the per-tool on/off switch.
    static func toolKey(serverID: String, toolName: String) -> String {
        "\(serverID)/\(toolName)"
    }
}
