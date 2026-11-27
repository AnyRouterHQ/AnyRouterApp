import Foundation

/// The quiet text after the icons: "Haiku 4.5 · $0.0012 · 42 tok/s". Each part is there only when it is known. The
/// price is for a paid reply only: a free model, Apple and a local model cost nothing, so they show no price.
struct FooterSummary: Equatable {
    var model: String?
    var price: String?
    var speed: String?

    /// In the order they are read.
    var parts: [String] { [model, price, speed].compactMap { $0 } }

    /// The parts joined with a middle dot. Nil when it has none.
    var line: String? { parts.isEmpty ? nil : parts.joined(separator: " · ") }

    /// With the "Show response details" setting off, or without metadata, only the model name stays.
    static func make(modelLabel: String?, metadata: ResponseMetadata?, showsDetails: Bool) -> FooterSummary {
        guard showsDetails, let metadata else { return FooterSummary(model: modelLabel) }
        let price = metadata.costUSD.flatMap { $0 > 0 ? PriceFormat.cost($0) : nil }
        return FooterSummary(model: modelLabel, price: price, speed: metadata.tokensPerSecond.map(ResponseFormat.speed))
    }
}

/// What sits under a finished reply: which icon buttons, the one line of text, the sources the answer used, and the
/// details a tap on that line opens. One pure function decides all of it, so visibility and order are tested without a view.
struct ReplyFooter: Equatable {
    /// In the order they are drawn. Share and Read Aloud live in the reply's long-press menu.
    enum Action: Hashable, Sendable { case copy, regenerate }

    /// A page the reply drew on.
    struct Source: Equatable, Identifiable, Sendable {
        let title: String
        /// Lowercase, without "www.".
        let host: String
        let url: URL
        /// The site's own icon. Never a favicon service: asking one would tell a third party which sites were used.
        let faviconURL: URL
        /// The same page written two ways has one id.
        let id: String

        /// Nil unless `link` is an http or https address with a host.
        init?(title: String, link: String) {
            guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let rawHost = url.host(), !rawHost.isEmpty,
                  let icon = URL(string: "https://\(rawHost)/favicon.ico")
            else { return nil }
            let lowered = rawHost.lowercased()
            let host = lowered.hasPrefix("www.") ? String(lowered.dropFirst(4)) : lowered
            let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
            self.title = title.isEmpty ? host : title
            self.host = host
            self.url = url
            self.faviconURL = icon
            self.id = host + path + (url.query.map { "?" + $0 } ?? "")
        }
    }

    var actions: [Action]
    /// "Gemma 4 E2B", "Haiku 4.5", "Apple". Nil when the reply carries no model name.
    var modelLabel: String?
    /// The text line: model, price and speed.
    var summary: FooterSummary
    /// Unique pages, in the order the model looked at them.
    var sources: [Source]
    /// What the sheet behind the summary shows. Nil with the setting off or when nothing is stored, so the line is plain text.
    var details: ReplyDetails?

    var hasDetails: Bool { details != nil }

    /// The favicon chain shows this many sites.
    static let maxFavicons = 3

    /// One source per site, first three: the sites in the favicon chain.
    var faviconSources: [Source] {
        var seen = Set<String>()
        return Array(sources.filter { seen.insert($0.host).inserted }.prefix(Self.maxFavicons))
    }

    /// "1 source", "53 sources". Nil without sources.
    var sourcesLabel: String? {
        switch sources.count {
        case 0: nil
        case 1: "1 source"
        default: "\(sources.count) sources"
        }
    }

    /// The footer of one reply, or nil while it is still being written or when it has no text.
    static func make(
        content: String, isStreaming: Bool, showsRegenerate: Bool, showsDetails: Bool,
        requestedName: String?, requestedID: String?, metadata: ResponseMetadata?, steps: [ToolStep],
        reasoningMs: Int? = nil
    ) -> ReplyFooter? {
        guard !isStreaming, !content.isEmpty else { return nil }
        var actions: [Action] = [.copy]
        if showsRegenerate { actions.append(.regenerate) }
        let name = displayName(requestedName: requestedName, requestedID: requestedID, metadata: metadata)
        let label = name.map(ModelShortLabel.make).flatMap { $0.isEmpty ? nil : $0 }
        let all = ReplyDetails.make(
            requestedName: requestedName, requestedID: requestedID, metadata: metadata, steps: steps, reasoningMs: reasoningMs)
        return ReplyFooter(
            actions: actions, modelLabel: label,
            summary: FooterSummary.make(modelLabel: label, metadata: metadata, showsDetails: showsDetails),
            sources: ReplySources.extract(from: steps), details: showsDetails && !all.isEmpty ? all : nil)
    }

    /// The model that wrote the reply: the one that served it (behind a router that is the routed model), else the one
    /// that was asked, else a name made from an id.
    static func displayName(requestedName: String?, requestedID: String?, metadata: ResponseMetadata?) -> String? {
        if let served = metadata?.servedModelName { return served }
        if let requestedName { return requestedName }
        if let id = metadata?.servedModelID { return ResponseFormat.prettyName(id) }
        if let requestedID { return ResponseFormat.prettyName(requestedID) }
        return nil
    }
}

/// The pages a reply drew on, read from its tool calls: the results of every search tool and the pages that were opened.
enum ReplySources {
    static func extract(from steps: [ToolStep]) -> [ReplyFooter.Source] {
        var seen = Set<String>()
        var found: [ReplyFooter.Source] = []
        for step in steps.flatMap(flattened) {
            guard let result = step.result, !result.isError else { continue }
            for source in sources(of: step.call, result: result) where seen.insert(source.id).inserted {
                found.append(source)
            }
        }
        return found
    }

    /// A call and, after it, the calls of the subagent it started.
    static func flattened(_ step: ToolStep) -> [ToolStep] {
        if let children = step.children { return [step] + children.flatMap(flattened) }
        return [step]
    }

    private static func sources(of call: ToolCall, result: ToolResult) -> [ReplyFooter.Source] {
        let name = call.name.lowercased()
        if name.contains("search") {
            return WebGrounding.parse(result.text).compactMap { ReplyFooter.Source(title: $0.title, link: $0.url) }
        }
        if name == "fetch_url", let link = argument("url", of: call), let page = ReplyFooter.Source(title: "", link: link) {
            return [page]
        }
        return []
    }

    private static func argument(_ key: String, of call: ToolCall) -> String? {
        let object = try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8)) as? [String: Any]
        return object?[key] as? String
    }
}

/// Everything the sheet behind the footer line shows, built from what is stored with the reply so it is the same after a
/// reload. A value that was not stored is left out, never shown as a dash; a section with no rows is left out.
struct ReplyDetails: Equatable {
    struct Row: Equatable {
        let label: String
        let value: String
    }

    struct Section: Equatable {
        let title: String
        let rows: [Row]
    }

    var sections: [Section]

    var isEmpty: Bool { sections.isEmpty }

    /// Plain text for a bug report: each section's title, then "label: value" lines, a blank line between sections.
    var copyAllText: String {
        sections.map { section in
            ([section.title] + section.rows.map { "\($0.label): \($0.value)" }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static func make(
        requestedName: String?, requestedID: String?, metadata: ResponseMetadata?, steps: [ToolStep], reasoningMs: Int?
    ) -> ReplyDetails {
        let model = [
            row("Name", ResponseFormat.title(requestedName: requestedName, requestedID: requestedID, metadata: metadata)
                ?? ReplyFooter.displayName(requestedName: requestedName, requestedID: requestedID, metadata: metadata)),
            row("ID", metadata?.servedModelID ?? requestedID),
            row("Engine", requestedID.flatMap(engine)),
            row("Provider", metadata?.provider),
        ]
        let speed = [
            row("First token", metadata?.ttftMs.map(ResponseFormat.seconds)),
            row("Speed", metadata?.tokensPerSecond.map(ResponseFormat.speed)),
            row("Total time", metadata?.totalMs.map(ResponseFormat.seconds)),
            row("Upstream latency", metadata?.upstreamLatencyMs.map(ResponseFormat.seconds)),
            row("Thinking time", reasoningMs.map(ResponseFormat.seconds)),
        ]
        let tokens = [
            row("Input", metadata?.promptTokens.map(String.init)),
            row("Output", metadata?.completionTokens.map(String.init)),
            row("Cached", metadata?.cachedTokens.map(String.init)),
            row("Cost", metadata?.costUSD.map(PriceFormat.cost)),
        ]
        let calls = steps.flatMap(ReplySources.flattened)
        let agent: [Row] = calls.isEmpty
            ? [] : [Row(label: "Tool calls", value: String(calls.count))] + calls.map {
                Row(label: $0.call.name, value: callOutcome($0.result))
            }
        let debug = [row("Request ID", metadata?.requestID)]
        let all = [
            Section(title: "Model", rows: model.compactMap { $0 }),
            Section(title: "Speed", rows: speed.compactMap { $0 }),
            Section(title: "Tokens and cost", rows: tokens.compactMap { $0 }),
            Section(title: "Agent", rows: agent),
            Section(title: "Context debug", rows: debug.compactMap { $0 }),
        ]
        return ReplyDetails(sections: all.filter { !$0.rows.isEmpty })
    }

    private static func row(_ label: String, _ value: String?) -> Row? {
        value.map { Row(label: label, value: $0) }
    }

    /// Where the model runs, from the id's prefix ("apple/", "gguf/", "mlx/", "anyrouter/"). Nil for an id it does not know.
    private static func engine(_ id: String) -> String? {
        switch id.split(separator: "/").first {
        case "apple": "Apple, on device"
        case "gguf": "llama.cpp, on device"
        case "mlx": "MLX, on device"
        case "anyrouter": "AnyRouter cloud"
        default: nil
        }
    }

    /// "Done · 1.2 KB", "Failed · 40 B", "Denied", "No result" for a call that never came back.
    private static func callOutcome(_ result: ToolResult?) -> String {
        guard let result else { return "No result" }
        if result.isError && result.text == ToolResult.deniedText { return "Denied" }
        let status = result.isError ? "Failed" : "Done"
        let bytes = result.text.utf8.count
        return bytes == 0 ? status : "\(status) · \(ResponseFormat.size(bytes))"
    }
}
