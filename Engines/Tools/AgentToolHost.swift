import Foundation

/// Every tool one chat request may use: the built-in tools, `web_search`, and the MCP tools, behind one `ToolHost`.
struct AgentToolHost: ToolHost {
    static let builtInTimeout: Double = 20

    let specs: [ToolSpec]
    private let builtIns: [String: any BuiltInTool]
    private let search: (match: WebSearchBinding.Match, client: MCPClient)?
    private let mcp: MCPToolHost?
    private let builtInTimeout: Double
    private let searchTimeout: Double

    init(
        builtIns: [any BuiltInTool],
        search: (match: WebSearchBinding.Match, client: MCPClient)?,
        mcp: MCPToolHost?,
        builtInTimeout: Double = AgentToolHost.builtInTimeout,
        searchTimeout: Double = 45
    ) {
        self.builtIns = Dictionary(builtIns.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.search = search
        self.mcp = mcp
        self.builtInTimeout = builtInTimeout
        self.searchTimeout = searchTimeout
        var specs = builtIns.map { $0.spec }
        if search != nil { specs.append(WebSearchBinding.spec) }
        specs += mcp?.specs ?? []
        self.specs = specs
    }

    /// Names the built-in tools and `web_search` use, so MCP tools never take them.
    static func reservedNames(builtIns: [any BuiltInTool], hasSearch: Bool) -> Set<String> {
        var names = Set(builtIns.map { $0.name })
        if hasSearch { names.insert(WebSearchBinding.name) }
        return names
    }

    func execute(_ call: ToolCall) async -> ToolResult {
        func result(_ text: String, error: Bool) -> ToolResult {
            ToolResult(callID: call.id, name: call.name, text: text, isError: error)
        }
        if let tool = builtIns[call.name] {
            guard let arguments = MCPToolHost.arguments(from: call.argumentsJSON) else {
                return result("The arguments are not a JSON object.", error: true)
            }
            let timeout = builtInTimeout
            do {
                let text = try await withDeadline(timeout) { try await tool.run(arguments) }
                return result(MCPToolHost.clip(text), error: false)
            } catch is CancellationError {
                return result("The tool call was cancelled.", error: true)
            } catch {
                return result(error.localizedDescription, error: true)
            }
        }
        if call.name == WebSearchBinding.name, let search {
            guard let arguments = MCPToolHost.arguments(from: call.argumentsJSON),
                let query = arguments["query"]?.string, !query.isEmpty
            else { return result("Missing the \"query\" argument.", error: true) }
            let client = search.client
            let toolName = search.match.tool.name
            let forwarded: JSONValue = .object([search.match.queryKey: .string(query)])
            let timeout = searchTimeout
            do {
                let answer = try await withDeadline(timeout) { try await client.callTool(name: toolName, arguments: forwarded) }
                return result(MCPToolHost.clip(answer.text), error: answer.isError)
            } catch is CancellationError {
                return result("The tool call was cancelled.", error: true)
            } catch {
                return result(error.localizedDescription, error: true)
            }
        }
        guard let mcp else { return result("Unknown tool: \(call.name).", error: true) }
        return await mcp.execute(call)
    }
}
