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
        /// The argument that takes the search text in the MCP tool's schema.
        var queryKey: String
    }

    private static let queryKeys = ["query", "q", "search", "keywords", "text"]

    /// The first search tool of a trusted server, with the name of its text argument.
    static func find(in enabled: [(server: MCPServer, tool: MCPTool)]) -> Match? {
        for item in enabled where item.server.isTrusted {
            let name = item.tool.name.lowercased()
            guard name.contains("search"), !name.hasPrefix("list_") else { continue }
            let properties = item.tool.inputSchema["properties"]?.object ?? [:]
            let strings = properties.filter { $0.value["type"]?.string == "string" }.map(\.key)
            if let key = queryKeys.first(where: { strings.contains($0) }) {
                return Match(server: item.server, tool: item.tool, queryKey: key)
            }
        }
        return nil
    }
}
