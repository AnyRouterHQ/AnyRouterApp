import Foundation

/// Text for the footer line and the details sheet of a reply: times, speed, sizes, names.
enum ResponseFormat {
    /// "0.6s", "2.1s", "12s". Under a tenth of a second reads "<0.1s".
    static func seconds(_ ms: Int) -> String {
        if ms < 100 { return "<0.1s" }
        if ms >= 10_000 { return "\(Int((Double(ms) / 1000).rounded()))s" }
        return String(format: "%.1fs", Double(ms) / 1000)
    }

    static func speed(_ tokensPerSecond: Double) -> String {
        "\(Int(tokensPerSecond.rounded())) tok/s"
    }

    /// "40 B", "1.2 KB", "3.4 MB": the size of a tool result.
    static func size(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    /// "AnyRouter → Nemotron 3.5 Bolt E4B" when a router picked the model, else the model's name.
    static func title(requestedName: String?, requestedID: String?, metadata: ResponseMetadata?) -> String? {
        let served = metadata?.servedModelName
        guard let requestedName else { return served }
        guard let served, served != requestedName else { return requestedName }
        let routed = requestedID?.hasPrefix("anyrouter/anyrouter/") == true
        return routed ? "\(requestedName) → \(served)" : served
    }

    /// A readable name from a model id when the model list does not know it:
    /// "nvidia/nemotron-3.5-bolt-e4b" gives "Nemotron 3.5 Bolt E4B".
    static func prettyName(_ id: String) -> String {
        let bare = id.split(separator: "/").last.map(String.init) ?? id
        return bare.split(separator: "-").map { token -> String in
            let text = String(token)
            let hasDigit = text.contains { $0.isNumber }
            let hasLetter = text.contains { $0.isLetter }
            if hasDigit && hasLetter && text.count <= 4 { return text.uppercased() }
            return text.prefix(1).uppercased() + text.dropFirst()
        }.joined(separator: " ")
    }
}
