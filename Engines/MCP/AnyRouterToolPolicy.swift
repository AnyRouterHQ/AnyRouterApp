import Foundation

/// Which tools of the AnyRouter server are safe to run without asking. The server marks its own core tools
/// read-only but not the Firecrawl ones, so those are judged by name: reading the web is read-only, creating,
/// changing or deleting monitors, crawling, interacting with pages, research (it can spend credits) and sending
/// feedback are not.
enum AnyRouterToolPolicy {
    /// `firecrawl__firecrawl_search` becomes `search`.
    static func bareName(_ name: String) -> String {
        var bare = name
        if bare.hasPrefix("firecrawl__") { bare.removeFirst("firecrawl__".count) }
        if bare.hasPrefix("firecrawl_") { bare.removeFirst("firecrawl_".count) }
        return bare
    }

    private static let readOnlyNames: Set<String> = [
        "search", "scrape", "map", "check_crawl_status", "agent_status",
        "monitor_check", "monitor_checks", "monitor_get", "monitor_list",
        "list_models", "recommend_model", "list_okf_concepts", "get_okf_concept", "get_system_status",
    ]

    /// The server's own `readOnlyHint` wins; without one the name decides.
    static func isReadOnly(_ tool: MCPTool) -> Bool {
        if let hint = tool.annotations?.readOnlyHint { return hint }
        let bare = bareName(tool.name)
        return readOnlyNames.contains(bare)
    }
}

extension MCPServer {
    /// A public web service the app ships (Exa and the like). Its tools are described in `ToolSourceCatalog`.
    var isCurated: Bool { ToolSourceCatalog.isCurated(serverID: id) }

    /// True when a tool of this server runs without the user's approval. Only the app's own server and the
    /// public services it ships are trusted to say so; a custom server's hints never count.
    func skipsApproval(_ tool: MCPTool) -> Bool {
        (isTrusted || isCurated) && AnyRouterToolPolicy.isReadOnly(tool)
    }

    /// New AnyRouter tools start on only when they read; the user turns the rest on, and each call still asks.
    /// A custom server's tools start on because the user added that server on purpose.
    func enabledByDefault(_ tool: MCPTool) -> Bool {
        if isCurated { return ToolSourceCatalog.pinned(serverID: id, tool: tool.name)?.onByDefault ?? false }
        return !isTrusted || AnyRouterToolPolicy.isReadOnly(tool)
    }
}
