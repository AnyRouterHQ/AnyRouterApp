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

/// Merges the built-in tools, the public web services, the AnyRouter MCP server (connected when signed in) and the
/// custom MCP servers. Built-in and source switches live here; MCP tool switches stay in `IntegrationsStore`.
@MainActor @Observable
final class ToolRegistry {
    private static let disabledKey = "tools.disabledBuiltIns"
    private static let sourceKey = "tools.sourceChoices"

    let integrations: IntegrationsStore
    /// Public web services with no account. The app passes `ToolSourceCatalog.publicSources`.
    let publicSources: [ToolSource]
    private let builtIns: [any BuiltInTool]
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var disabledBuiltIns: Set<String>
    /// What the user chose per source. A source with no entry follows its default.
    private(set) var sourceChoices: [String: Bool]

    init(
        integrations: IntegrationsStore,
        builtIns: [any BuiltInTool] = ToolRegistry.standardBuiltIns(),
        publicSources: [ToolSource] = [],
        defaults: UserDefaults = .standard
    ) {
        self.integrations = integrations
        self.builtIns = builtIns
        self.publicSources = publicSources
        self.defaults = defaults
        disabledBuiltIns = Set(defaults.stringArray(forKey: Self.disabledKey) ?? [])
        sourceChoices = defaults.dictionary(forKey: Self.sourceKey) as? [String: Bool] ?? [:]
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

    // MARK: Sources

    /// Every source Settings lists, in section order.
    var sources: [ToolSource] {
        [ToolSourceCatalog.device] + publicSources + [ToolSourceCatalog.anyRouter]
            + integrations.customServers.map(ToolSourceCatalog.custom)
    }

    /// The sources the composer menu lists: AnyRouter only while the user is signed in.
    var menuSources: [ToolSource] {
        sources.filter { $0.id != ToolSourceCatalog.anyRouter.id || integrations.signedIn }
    }

    /// The user's choice, else the default for this sign-in state and model.
    func isOn(_ source: ToolSource, modelSource: ModelSource? = nil) -> Bool {
        isOn(source, in: ToolSituation(signedIn: integrations.signedIn, modelSource: modelSource))
    }

    /// `forced` are the sources the user named with @ for this request: only they are on, whatever their switch says.
    private func isOn(_ source: ToolSource, in situation: ToolSituation, forced: Set<String> = []) -> Bool {
        if !forced.isEmpty { return forced.contains(source.id) }
        return sourceChoices[source.id] ?? source.isOnByDefault(in: situation)
    }

    func setSource(_ source: ToolSource, on: Bool) {
        sourceChoices[source.id] = on
        defaults.set(sourceChoices, forKey: Self.sourceKey)
    }

    private func source(for server: MCPServer) -> ToolSource {
        if server.id == MCPServer.anyRouter.id { return ToolSourceCatalog.anyRouter }
        return publicSources.first { $0.server?.id == server.id } ?? ToolSourceCatalog.custom(server)
    }

    /// The MCP tools a chat may use: those of connected servers and public services whose source and tool are on.
    private func activeMCPTools(_ situation: ToolSituation, forced: Set<String> = []) -> [(server: MCPServer, tool: MCPTool)] {
        var list = integrations.enabledTools.filter { isOn(source(for: $0.server), in: situation, forced: forced) }
        for source in publicSources where isOn(source, in: situation, forced: forced) {
            guard let server = source.server else { continue }
            for pin in source.tools {
                let tool = pin.mcpTool
                if integrations.isEnabled(tool, on: server) { list.append((server: server, tool: tool)) }
            }
        }
        return list
    }

    // MARK: Listing

    /// Every built-in tool Settings lists. `read_attachment` is listed always but only offered to a model in a chat with attachments.
    var listedBuiltIns: [any BuiltInTool] { builtIns + [ReadAttachmentTool(provider: NoAttachments())] }

    var searchMatch: WebSearchBinding.Match? { WebSearchBinding.find(in: integrations.enabledTools) }

    /// The AnyRouter scrape tool `fetch_url` prefers while signed in. Only while `fetch_url` itself is on.
    var scrapeMatch: WebSearchBinding.Match? {
        isBuiltInEnabled(FetchURLTool.toolName) ? WebSearchBinding.findScrape(in: integrations.enabledTools) : nil
    }

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
        for tool in listedBuiltIns {
            list.append(RegisteredTool(
                id: "builtin/\(tool.name)", source: .builtIn, name: tool.name, title: tool.title,
                description: tool.description, inputSchemaJSON: tool.inputSchemaJSON, needsApproval: false,
                enabled: isBuiltInEnabled(tool.name)))
        }
        for source in publicSources {
            guard let server = source.server else { continue }
            for pin in source.tools {
                list.append(RegisteredTool(
                    id: IntegrationsLogic.toolKey(serverID: server.id, toolName: pin.name),
                    source: .mcp(serverID: server.id, serverName: server.name),
                    name: pin.name, title: pin.title, description: pin.summary,
                    inputSchemaJSON: pin.inputSchemaJSON, needsApproval: false,
                    enabled: integrations.isEnabled(pin.mcpTool, on: server)))
            }
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
                    needsApproval: !server.skipsApproval(tool),
                    enabled: integrations.isEnabled(tool, on: server)))
            }
        }
        return list
    }

    // MARK: Host

    /// What one request may use, before the connection is considered.
    private struct HostPlan {
        var match: WebSearchBinding.Match?
        var scrape: WebSearchBinding.Match?
        var builtIns: [any BuiltInTool]
        var mcpTools: [(server: MCPServer, tool: MCPTool)]

        /// Search, page reading and every MCP tool need the connection.
        var usesNetwork: Bool { match != nil || scrape != nil || !mcpTools.isEmpty || builtIns.contains { $0.needsNetwork } }

        mutating func dropNetworkTools() {
            match = nil
            scrape = nil
            mcpTools = []
            builtIns.removeAll { $0.needsNetwork }
        }
    }

    private func plan(for context: ToolContext) -> HostPlan {
        let situation = ToolSituation(signedIn: integrations.signedIn, modelSource: context.modelSource)
        let deviceOn = isOn(ToolSourceCatalog.device, in: situation, forced: context.forcedSourceIDs)
        var mcpTools = activeMCPTools(situation, forced: context.forcedSourceIDs)
        let match = WebSearchBinding.find(in: mcpTools).flatMap { isBuiltInEnabled(WebSearchBinding.name) ? $0 : nil }
        let scrape = deviceOn && isBuiltInEnabled(FetchURLTool.toolName) ? WebSearchBinding.findScrape(in: mcpTools) : nil
        if let match {
            // The model sees `web_search`, not the tool behind it twice.
            mcpTools.removeAll { $0.server.id == match.server.id && $0.tool.name == match.tool.name }
        }
        if let scrape {
            mcpTools.removeAll { $0.server.id == scrape.server.id && $0.tool.name == scrape.tool.name }
        }
        var builtIns = deviceOn ? self.builtIns.filter { isBuiltInEnabled($0.name) } : []
        if deviceOn, !context.attachments.isEmpty, isBuiltInEnabled("read_attachment") {
            builtIns.append(ReadAttachmentTool(provider: ThreadAttachments(attachments: context.attachments)))
        }
        return HostPlan(match: match, scrape: scrape, builtIns: builtIns, mcpTools: mcpTools)
    }

    /// The device is offline and this request would have used a web tool. The chat tells the reader.
    func skipsOffline(_ context: ToolContext) -> Bool {
        context.isOffline && self.plan(for: context).usesNetwork
    }

    /// The tools for one chat request, or nil when none is on. Offline, the web tools are left out.
    func makeHost(approver: any ToolApproving, context: ToolContext = ToolContext()) -> AgentToolHost? {
        var plan = self.plan(for: context)
        if context.isOffline { plan.dropNetworkTools() }
        let (match, scrape, builtIns, mcpTools) = (plan.match, plan.scrape, plan.builtIns, plan.mcpTools)
        guard match != nil || !builtIns.isEmpty || !mcpTools.isEmpty else { return nil }

        let reserved = AgentToolHost.reservedNames(builtIns: builtIns, hasSearch: match != nil)
        let mcpHost = mcpTools.isEmpty ? nil : integrations.makeToolHost(enabled: mcpTools, approver: approver, reserved: reserved)
        let search = match.map { (match: $0, client: integrations.client(for: $0.server)) }
        let fetch = scrape.map { (match: $0, client: integrations.client(for: $0.server)) }
        return AgentToolHost(
            builtIns: builtIns, search: search, mcp: mcpHost, fetch: fetch,
            approver: approver, exfiltration: ExfiltrationGuard(userTexts: context.userTexts),
            profile: ToolProfile.forModel(context.modelSource))
    }
}
