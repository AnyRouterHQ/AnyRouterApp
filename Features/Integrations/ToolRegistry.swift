import Foundation
import Observation

/// One tool as Settings and the chat see it, whatever its source.
struct RegisteredTool: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case builtIn
        case mcp(serverID: String, serverName: String)
    }

    var id: String
    var source: Source
    var name: String
    var title: String
    var description: String
    var inputSchemaJSON: String
    var needsApproval: Bool
    var enabled: Bool
}

/// Merges the built-in tools, the AnyRouter MCP server (connected when signed in) and the custom MCP servers.
/// Built-in switches live here; MCP switches stay in `IntegrationsStore`.
@MainActor @Observable
final class ToolRegistry {
    private static let disabledKey = "tools.disabledBuiltIns"

    let integrations: IntegrationsStore
    private let builtIns: [any BuiltInTool]
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var disabledBuiltIns: Set<String>
    /// Set by the attachments feature. Without it `read_attachment` does not exist.
    @ObservationIgnored var attachments: (any AttachmentTextProviding)?

    init(
        integrations: IntegrationsStore,
        builtIns: [any BuiltInTool] = ToolRegistry.standardBuiltIns(),
        defaults: UserDefaults = .standard
    ) {
        self.integrations = integrations
        self.builtIns = builtIns
        self.defaults = defaults
        disabledBuiltIns = Set(defaults.stringArray(forKey: Self.disabledKey) ?? [])
    }

    static func standardBuiltIns(session: URLSession = .shared) -> [any BuiltInTool] {
        [FetchURLTool(session: session), CurrentDateTimeTool(), CalculatorTool()]
    }

    // MARK: Switches

    func isBuiltInEnabled(_ name: String) -> Bool { !disabledBuiltIns.contains(name) }

    func setBuiltIn(_ name: String, enabled: Bool) {
        if enabled { disabledBuiltIns.remove(name) } else { disabledBuiltIns.insert(name) }
        defaults.set(disabledBuiltIns.sorted(), forKey: Self.disabledKey)
    }

    // MARK: Listing

    /// The built-in tools that exist right now: `web_search` only while a search tool is connected, `read_attachment` only with attachments.
    var availableBuiltIns: [any BuiltInTool] {
        var all = builtIns
        if let attachments { all.append(ReadAttachmentTool(provider: attachments)) }
        return all
    }

    var searchMatch: WebSearchBinding.Match? { WebSearchBinding.find(in: integrations.enabledTools) }

    /// Everything Settings lists, with its switch state. MCP tools of servers that are not connected are not listed.
    var tools: [RegisteredTool] {
        var list: [RegisteredTool] = []
        if searchMatch != nil {
            list.append(RegisteredTool(
                id: "builtin/\(WebSearchBinding.name)", source: .builtIn, name: WebSearchBinding.name,
                title: "Search the web", description: WebSearchBinding.description,
                inputSchemaJSON: WebSearchBinding.inputSchemaJSON, needsApproval: false,
                enabled: isBuiltInEnabled(WebSearchBinding.name)))
        }
        for tool in availableBuiltIns {
            list.append(RegisteredTool(
                id: "builtin/\(tool.name)", source: .builtIn, name: tool.name, title: tool.title,
                description: tool.description, inputSchemaJSON: tool.inputSchemaJSON, needsApproval: false,
                enabled: isBuiltInEnabled(tool.name)))
        }
        for server in integrations.servers {
            let state = integrations.state(for: server)
            guard state.status == .connected else { continue }
            for tool in state.tools {
                list.append(RegisteredTool(
                    id: IntegrationsLogic.toolKey(serverID: server.id, toolName: tool.name),
                    source: .mcp(serverID: server.id, serverName: server.name),
                    name: tool.name, title: tool.displayName, description: tool.description ?? tool.displayName,
                    inputSchemaJSON: tool.inputSchema.jsonString(),
                    needsApproval: !(tool.isReadOnly && server.isTrusted),
                    enabled: integrations.isEnabled(tool, on: server)))
            }
        }
        return list
    }

    // MARK: Host

    /// The tools for one chat request, or nil when none is on.
    func makeHost(approver: any ToolApproving) -> AgentToolHost? {
        var mcpTools = integrations.enabledTools
        let match = searchMatch.flatMap { isBuiltInEnabled(WebSearchBinding.name) ? $0 : nil }
        if let match {
            // The model sees `web_search`, not the tool behind it twice.
            mcpTools.removeAll { $0.server.id == match.server.id && $0.tool.name == match.tool.name }
        }
        let builtIns = availableBuiltIns.filter { isBuiltInEnabled($0.name) }
        guard match != nil || !builtIns.isEmpty || !mcpTools.isEmpty else { return nil }

        let reserved = AgentToolHost.reservedNames(builtIns: builtIns, hasSearch: match != nil)
        let mcpHost = mcpTools.isEmpty ? nil : integrations.makeToolHost(enabled: mcpTools, approver: approver, reserved: reserved)
        let search = match.map { (match: $0, client: integrations.client(for: $0.server)) }
        return AgentToolHost(builtIns: builtIns, search: search, mcp: mcpHost)
    }
}
