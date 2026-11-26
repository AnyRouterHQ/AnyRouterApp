import Foundation

enum IntegrationsLogic {
    enum URLProblem: LocalizedError, Equatable {
        case empty
        case notHTTPS
        case invalid
        case duplicate

        var errorDescription: String? {
            switch self {
            case .empty: return "Enter the server URL."
            case .notHTTPS: return "Use an https:// URL. Plain http is only allowed for localhost."
            case .invalid: return "That is not a valid server URL."
            case .duplicate: return "This server is already added."
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

    /// Key of the per-tool on/off switch.
    static func toolKey(serverID: String, toolName: String) -> String {
        "\(serverID)/\(toolName)"
    }
}
