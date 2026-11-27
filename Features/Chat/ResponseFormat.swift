import Foundation

/// Text for the details under a reply: model, cost, timings, tokens.
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

    static func tokens(prompt: Int?, completion: Int?) -> String? {
        switch (prompt, completion) {
        case let (p?, c?): return "\(p) in / \(c) out"
        case let (p?, nil): return "\(p) in"
        case let (nil, c?): return "\(c) out"
        case (nil, nil): return nil
        }
    }

    struct Field: Equatable {
        let label: String
        let value: String
    }

    static let requestLabel = "Request"

    /// Under the model name: cost, timings, tokens and ids. Missing values are left out.
    static func expanded(_ metadata: ResponseMetadata) -> [Field] {
        var fields: [Field] = []
        func add(_ label: String, _ value: String?) { if let value { fields.append(Field(label: label, value: value)) } }
        add("Model", metadata.servedModelID)
        add("Provider", metadata.provider)
        add("Cost", metadata.costUSD.map(PriceFormat.cost))
        add("Total", metadata.totalMs.map(seconds))
        add("Speed", metadata.tokensPerSecond.map(speed))
        add("Tokens", tokens(prompt: metadata.promptTokens, completion: metadata.completionTokens))
        add("Cached tokens", metadata.cachedTokens.map(String.init))
        add("Upstream latency", metadata.upstreamLatencyMs.map(seconds))
        add(requestLabel, metadata.requestID)
        return fields
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
