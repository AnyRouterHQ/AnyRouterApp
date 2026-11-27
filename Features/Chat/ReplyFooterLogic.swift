import Foundation

/// What sits under a finished reply: which actions, the short model name, the sources the answer used, and whether a
/// tap opens more details. One pure function decides all of it, so visibility and order are tested without a view.
struct ReplyFooter: Equatable {
    /// In the order they are drawn.
    enum Action: Hashable, Sendable { case copy, share, readAloud, regenerate }

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
    /// Unique pages, in the order the model looked at them.
    var sources: [Source]
    /// Cost, speed and tokens are known and the setting is on, so the model name opens them.
    var hasDetails: Bool
    /// Time to the first word, "0.4s", when the setting is on and the time was measured. It sits after the model name.
    var ttft: String?

    /// What the row says after the sources: "Sonnet 4.6 · 0.4s", or one of them. Nil when it has neither.
    var modelLine: String? {
        let parts = [modelLabel, ttft].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

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
        requestedName: String?, requestedID: String?, metadata: ResponseMetadata?, steps: [ToolStep]
    ) -> ReplyFooter? {
        guard !isStreaming, !content.isEmpty else { return nil }
        var actions: [Action] = [.copy, .share, .readAloud]
        if showsRegenerate { actions.append(.regenerate) }
        let name = displayName(requestedName: requestedName, requestedID: requestedID, metadata: metadata)
        let label = name.map(ModelShortLabel.make).flatMap { $0.isEmpty ? nil : $0 }
        let hasDetails = showsDetails && metadata.map { !ResponseFormat.expanded($0).isEmpty } == true
        let ttft = showsDetails ? metadata?.ttftMs.map(ResponseFormat.seconds) : nil
        return ReplyFooter(
            actions: actions, modelLabel: label, sources: ReplySources.extract(from: steps), hasDetails: hasDetails, ttft: ttft)
    }

    /// The model that wrote the reply: the one that served it (behind a router that is the routed model), else the one
    /// that was asked, else a name made from an id.
    private static func displayName(requestedName: String?, requestedID: String?, metadata: ResponseMetadata?) -> String? {
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
    private static func flattened(_ step: ToolStep) -> [ToolStep] {
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
