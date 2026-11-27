import Foundation

/// Who receives what a web tool sends, named in the first-use note.
struct ToolRecipient: Hashable, Sendable {
    var name: String
    var site: String
}

/// What decides whether a source is on before the user chooses: sign-in state and the model that runs the chat.
struct ToolSituation: Equatable, Sendable {
    var signedIn: Bool
    var modelSource: ModelSource?

    /// Apple's model and local models cannot use AnyRouter's own web search.
    var isOnDeviceModel: Bool { modelSource == .apple || modelSource == .gguf || modelSource == .mlx }
}

/// A tool the app ships the description of. It needs no `tools/list` round trip, and its text is short on purpose
/// so a small model can read it. The names and arguments were checked against the live servers.
struct PinnedTool: Hashable, Sendable {
    var name: String
    var title: String
    var symbol: String
    /// One line. Shown in Settings and sent to the model.
    var summary: String
    var inputSchemaJSON: String
    var onByDefault = true
    /// Arguments filled in when the model leaves them out.
    var fills: [String: JSONValue] = [:]
    /// `["objective": "query"]` copies `query` into `objective` when the model gave none.
    var copies: [String: String] = [:]
    /// The argument that carries the user's search words, when there is one.
    var queryArgument: String?

    /// The same tool as an MCP server would list it. Public servers are read-only, which the app checked.
    var mcpTool: MCPTool {
        MCPTool(
            name: name, title: title, description: summary,
            inputSchema: JSONValue.parse(inputSchemaJSON) ?? .object(["type": .string("object")]),
            annotations: MCPTool.Annotations(title: title, readOnlyHint: true, destructiveHint: false, openWorldHint: true))
    }
}

/// One place tools come from: this device, a public web service, AnyRouter, or a server the user added.
/// Settings, the composer menu and the chat's tool list all read this table, so a new source is one entry.
struct ToolSource: Identifiable, Hashable, Sendable {
    enum Group: Int, CaseIterable, Identifiable, Sendable {
        case onDevice, web, anyRouter, custom

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .onDevice: "On device"
            case .web: "Web"
            case .anyRouter: "AnyRouter"
            case .custom: "Custom servers"
            }
        }
    }

    /// An SF Symbol, or a template image in `Design/Assets.xcassets`.
    enum Icon: Hashable, Sendable {
        case symbol(String)
        case asset(String)
    }

    enum DefaultState: Hashable, Sendable {
        case on
        case off
        /// On when AnyRouter cannot search for the chat: the user is signed out, or the model runs on the device.
        case searchFallback
    }

    var id: String
    var group: Group
    var title: String
    var subtitle: String
    var icon: Icon
    /// What the source needs from the user. `.none` means no account and no key; a token is never sent to such a server.
    var auth: MCPServer.Auth
    var defaultState: DefaultState
    /// Set for services outside the app and AnyRouter. Names the party that receives the tool's text.
    var recipient: ToolRecipient?
    var server: MCPServer?
    /// The tools the app lists itself. Empty for sources whose tools are read from the server or the device.
    var tools: [PinnedTool] = []

    var requiresSignIn: Bool { auth == .anyRouterSignIn }

    func isOnByDefault(in situation: ToolSituation) -> Bool {
        switch defaultState {
        case .on: true
        case .off: false
        case .searchFallback: !situation.signedIn || situation.isOnDeviceModel
        }
    }
}

/// The table of sources the app knows.
enum ToolSourceCatalog {
    static let device = ToolSource(
        id: "device", group: .onDevice, title: "On this device",
        subtitle: "Date and time, calculator, web pages, attachments",
        icon: .symbol("iphone"), auth: .none, defaultState: .on, recipient: nil, server: nil)

    static let exa = ToolSource(
        id: "exa", group: .web, title: "Exa",
        subtitle: "Search the web and read pages. No account needed.",
        icon: .asset("Logo-exa"), auth: .none, defaultState: .searchFallback,
        recipient: ToolRecipient(name: "Exa", site: "exa.ai"),
        server: MCPServer(id: "exa", name: "Exa", url: URL(string: "https://mcp.exa.ai/mcp")!, auth: .none),
        tools: [
            PinnedTool(
                name: "web_search_exa", title: "Search the web", symbol: "magnifyingglass",
                summary: "Search the web. Returns the best pages with text from each.",
                inputSchemaJSON: #"{"type":"object","properties":{"query":{"type":"string","description":"What to look for, in plain words"},"numResults":{"type":"integer","description":"How many results, 1 to 10"}},"required":["query"]}"#,
                fills: ["numResults": .number(5)], copies: ["objective": "query"], queryArgument: "query"),
            PinnedTool(
                name: "web_fetch_exa", title: "Read web pages", symbol: "doc.text.magnifyingglass",
                summary: "Read the text of web pages from their addresses.",
                inputSchemaJSON: #"{"type":"object","properties":{"urls":{"type":"array","items":{"type":"string"},"description":"Page addresses"}},"required":["urls"]}"#),
        ])

    static let deepWiki = ToolSource(
        id: "deepwiki", group: .web, title: "DeepWiki",
        subtitle: "Ask about public GitHub projects. No account needed.",
        icon: .symbol("books.vertical"), auth: .none, defaultState: .on,
        recipient: ToolRecipient(name: "DeepWiki", site: "deepwiki.com"),
        server: MCPServer(id: "deepwiki", name: "DeepWiki", url: URL(string: "https://mcp.deepwiki.com/mcp")!, auth: .none),
        tools: [
            PinnedTool(
                name: "ask_wiki_question", title: "Ask about a repository", symbol: "text.bubble",
                summary: "Ask a question about a public GitHub repository.",
                inputSchemaJSON: #"{"type":"object","properties":{"repoName":{"type":"string","description":"owner/repo"},"question":{"type":"string"}},"required":["repoName","question"]}"#,
                queryArgument: "question"),
            PinnedTool(
                name: "read_wiki_structure", title: "List documentation topics", symbol: "list.bullet.indent",
                summary: "List the documentation topics of a public GitHub repository.",
                inputSchemaJSON: #"{"type":"object","properties":{"repoName":{"type":"string","description":"owner/repo"}},"required":["repoName"]}"#,
                onByDefault: false),
            PinnedTool(
                name: "read_wiki_contents", title: "Read documentation", symbol: "book",
                summary: "Read the documentation of a public GitHub repository.",
                inputSchemaJSON: #"{"type":"object","properties":{"repoName":{"type":"string","description":"owner/repo"}},"required":["repoName"]}"#,
                onByDefault: false),
        ])

    static let microsoftLearn = ToolSource(
        id: "mslearn", group: .web, title: "Microsoft Learn",
        subtitle: "Search Microsoft and Azure documentation. No account needed.",
        icon: .asset("Logo-microsoft"), auth: .none, defaultState: .on,
        recipient: ToolRecipient(name: "Microsoft Learn", site: "learn.microsoft.com"),
        server: MCPServer(id: "mslearn", name: "Microsoft Learn", url: URL(string: "https://learn.microsoft.com/api/mcp")!, auth: .none),
        tools: [
            PinnedTool(
                name: "microsoft_docs_search", title: "Search documentation", symbol: "magnifyingglass",
                summary: "Search Microsoft and Azure documentation.",
                inputSchemaJSON: #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}"#,
                queryArgument: "query"),
            PinnedTool(
                name: "microsoft_docs_fetch", title: "Read a documentation page", symbol: "doc.text",
                summary: "Read a Microsoft Learn page from its address.",
                inputSchemaJSON: #"{"type":"object","properties":{"url":{"type":"string"}},"required":["url"]}"#),
            PinnedTool(
                name: "microsoft_code_sample_search", title: "Search code samples", symbol: "curlybraces",
                summary: "Find code samples in Microsoft documentation.",
                inputSchemaJSON: #"{"type":"object","properties":{"query":{"type":"string"},"language":{"type":"string","description":"For example csharp or python"}},"required":["query"]}"#,
                onByDefault: false, queryArgument: "query"),
        ])

    static let anyRouter = ToolSource(
        id: MCPServer.anyRouter.id, group: .anyRouter, title: "AnyRouter",
        subtitle: "Models, system status and web tools with your account",
        icon: .asset("BrandMark"), auth: .anyRouterSignIn, defaultState: .on,
        recipient: nil, server: .anyRouter)

    /// Public services that need no account and no key. The app talks to them without a token.
    static let publicSources: [ToolSource] = [exa, deepWiki, microsoftLearn]

    /// The icon of every server the user added.
    static let customIcon: ToolSource.Icon = .symbol("server.rack")

    /// A server the user added.
    static func custom(_ server: MCPServer) -> ToolSource {
        ToolSource(
            id: server.id, group: .custom, title: server.name, subtitle: server.url.host() ?? server.url.absoluteString,
            icon: customIcon, auth: server.auth, defaultState: .on, recipient: nil, server: server)
    }

    // MARK: Lookups

    static func isCurated(serverID: String) -> Bool {
        publicSources.contains { $0.server?.id == serverID }
    }

    static func recipient(forServerID id: String) -> ToolRecipient? {
        publicSources.first { $0.server?.id == id }?.recipient
    }

    static func pinned(serverID: String, tool name: String) -> PinnedTool? {
        publicSources.first { $0.server?.id == serverID }?.tools.first { $0.name == name }
    }

    /// The argument of a tool that carries search words, so a long passage of the chat can be caught in it.
    static func queryArgument(forTool name: String) -> String? {
        if name == WebSearchBinding.name { return "query" }
        for source in publicSources {
            if let tool = source.tools.first(where: { $0.name == name }) { return tool.queryArgument }
        }
        return nil
    }

    /// The arguments the model gave, plus what the tool needs that a small model tends to leave out.
    static func completing(_ arguments: JSONValue, serverID: String, tool: String) -> JSONValue {
        guard var fields = arguments.object, let pin = pinned(serverID: serverID, tool: tool) else { return arguments }
        for (key, value) in pin.fills where fields[key] == nil { fields[key] = value }
        for (target, source) in pin.copies where fields[target] == nil {
            if let value = fields[source] { fields[target] = value }
        }
        return .object(fields)
    }

    private static let toolSymbols: [(keyword: String, symbol: String)] = [
        ("calculator", "function"), ("attachment", "paperclip"), ("date", "calendar"), ("time", "clock"),
        ("search", "magnifyingglass"), ("scrape", "doc.text.magnifyingglass"), ("fetch", "arrow.down.doc"),
        ("crawl", "point.3.connected.trianglepath.dotted"), ("map", "map"), ("screenshot", "camera.viewfinder"),
        ("interact", "hand.tap"), ("monitor", "bell"), ("research", "text.book.closed"), ("agent", "sparkles"),
        ("model", "cpu"), ("status", "waveform.path.ecg"), ("okf", "books.vertical"), ("credit", "creditcard"),
        ("feedback", "bubble.left"),
    ]

    /// An SF Symbol for a tool the app does not list itself, by the words in its name.
    static func symbol(forTool name: String) -> String {
        let lowered = name.lowercased()
        return toolSymbols.first { lowered.contains($0.keyword) }?.symbol ?? "wrench.and.screwdriver"
    }
}
