import Foundation

/// `web_search` is not code of its own: it forwards to the search tool of the AnyRouter MCP server
/// (Firecrawl, when the user connected it). With no such tool, `web_search` does not exist.
struct WebSearchBinding: Sendable {
    static let name = "web_search"
    static let description = "Search the web. Returns the top results with titles, links and snippets."
    static let inputSchemaJSON = #"{"type":"object","properties":{"query":{"type":"string","description":"What to search for"}},"required":["query"]}"#

    static var spec: ToolSpec {
        ToolSpec(name: name, title: "Search the web", description: description, inputSchemaJSON: inputSchemaJSON, isReadOnly: true)
    }

    struct Match: Equatable {
        var server: MCPServer
        var tool: MCPTool
        /// The argument that takes the search text (or the URL) in the MCP tool's schema.
        var queryKey: String
        /// Arguments to send along when the schema has them.
        var extra: [String: JSONValue] = [:]
    }

    private static let queryKeys = ["query", "q", "search", "keywords", "text"]

    /// The search tool of a trusted server, with the name of its text argument.
    static func find(in enabled: [(server: MCPServer, tool: MCPTool)]) -> Match? {
        match(bare: "search", keys: queryKeys, in: enabled)
    }

    /// The scrape tool of a trusted server: it reads pages better than the on-device `fetch_url`.
    static func findScrape(in enabled: [(server: MCPServer, tool: MCPTool)]) -> Match? {
        guard var found = match(bare: "scrape", keys: ["url"], in: enabled) else { return nil }
        if found.tool.inputSchema["properties"]?["onlyMainContent"] != nil { found.extra["onlyMainContent"] = .bool(true) }
        return found
    }

    private static func match(
        bare: String, keys: [String], in enabled: [(server: MCPServer, tool: MCPTool)]
    ) -> Match? {
        for item in enabled where item.server.isTrusted && AnyRouterToolPolicy.bareName(item.tool.name) == bare {
            let properties = item.tool.inputSchema["properties"]?.object ?? [:]
            let strings = properties.filter { $0.value["type"]?.string == "string" }.map(\.key)
            if let key = keys.first(where: { strings.contains($0) }) {
                return Match(server: item.server, tool: item.tool, queryKey: key)
            }
        }
        return nil
    }
}
