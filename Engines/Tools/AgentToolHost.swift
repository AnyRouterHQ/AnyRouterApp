import Foundation

/// Every tool one chat request may use: the built-in tools, `web_search`, and the MCP tools, behind one `ToolHost`.
struct AgentToolHost: ToolHost {
    static let builtInTimeout: Double = 20

    let specs: [ToolSpec]
    private let builtIns: [String: any BuiltInTool]
    private let search: (match: WebSearchBinding.Match, client: MCPClient)?
    /// When set, `fetch_url` tries the AnyRouter scrape tool first and falls back to the on-device fetch.
    private let fetch: (match: WebSearchBinding.Match, client: MCPClient)?
    private let mcp: MCPToolHost?
    private let builtInTimeout: Double
    private let searchTimeout: Double
    private let approver: (any ToolApproving)?
    private let exfiltration: ExfiltrationGuard
    private let profile: ToolProfile
    /// Every tool the host can run, including those the profile left out of `specs`: a call to one still gets the checks.
    private let allSpecs: [ToolSpec]

    /// `approver` is asked in the cases `ExfiltrationGuard` describes; without one such calls are refused.
    init(
        builtIns: [any BuiltInTool],
        search: (match: WebSearchBinding.Match, client: MCPClient)?,
        mcp: MCPToolHost?,
        fetch: (match: WebSearchBinding.Match, client: MCPClient)? = nil,
        builtInTimeout: Double = AgentToolHost.builtInTimeout,
        searchTimeout: Double = 45,
        approver: (any ToolApproving)? = nil,
        exfiltration: ExfiltrationGuard = ExfiltrationGuard(userTexts: []),
        profile: ToolProfile = .full
    ) {
        self.profile = profile
        self.approver = approver
        self.exfiltration = exfiltration
        self.builtIns = Dictionary(builtIns.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.search = search
        self.mcp = mcp
        self.fetch = fetch
        self.builtInTimeout = builtInTimeout
        self.searchTimeout = searchTimeout
        var specs = builtIns.map { $0.spec }
        if search != nil { specs.append(WebSearchBinding.spec) }
        specs += mcp?.specs ?? []
        allSpecs = specs
        self.specs = profile.shaped(specs)
    }

    /// Names the built-in tools and `web_search` use, so MCP tools never take them.
    static func reservedNames(builtIns: [any BuiltInTool], hasSearch: Bool) -> Set<String> {
        var names = Set(builtIns.map { $0.name })
        if hasSearch { names.insert(WebSearchBinding.name) }
        return names
    }

    func sourceID(forTool name: String) -> String? {
        if builtIns[name] != nil { return ToolSourceCatalog.device.id }
        if search != nil, name == WebSearchBinding.name { return ToolSourceCatalog.anyRouter.id }
        return mcp?.sourceID(forTool: name)
    }

    func execute(_ call: ToolCall) async -> ToolResult {
        if let request = approvalRequest(for: call) {
            guard let approver, await approver.decide(request) != .deny else {
                return ToolResult(callID: call.id, name: call.name, text: ToolResult.deniedText, isError: true)
            }
        }
        var result = await run(call)
        result.text = profile.clipped(result.text)
        return result
    }

    /// A built-in write or external call, asked every time; or a call that needs no approval of its own but could carry
    /// chat text out: a URL the user never wrote, or a search that repeats a long passage of the chat. MCP tools that
    /// need approval already ask in `MCPToolHost`.
    private func approvalRequest(for call: ToolCall) -> ToolApprovalRequest? {
        if let tool = builtIns[call.name], !tool.sideEffect.isRead, !tool.undoesInsteadOfAsking {
            // A reason keeps "Always allow" off the card and the dialog.
            let reason = tool.sideEffect == .write ? "This changes data in the app." : "This sends something outside the app."
            return ToolApprovalRequest(serverName: "This device", spec: tool.spec, call: call, reason: reason)
        }
        guard let spec = allSpecs.first(where: { $0.name == call.name }), spec.isReadOnly,
            let arguments = MCPToolHost.arguments(from: call.argumentsJSON)
        else { return nil }
        let urls = exfiltration.unsuppliedURLs(in: arguments)
        let reason: String
        if !urls.isEmpty {
            reason = "This address is not in your messages."
        } else if let key = ToolSourceCatalog.queryArgument(forTool: call.name), let query = arguments[key]?.string,
            exfiltration.repeatsUserText(query) {
            reason = "This search repeats a long passage of the chat."
        } else {
            return nil
        }
        let onDevice = builtIns[call.name] != nil && !(call.name == FetchURLTool.toolName && fetch != nil)
        return ToolApprovalRequest(
            serverName: onDevice ? "This device" : (mcp?.serverName(for: call.name) ?? "AnyRouter"), spec: spec, call: call, reason: reason, urls: urls)
    }

    private func run(_ call: ToolCall) async -> ToolResult {
        func result(_ text: String, error: Bool) -> ToolResult {
            ToolResult(callID: call.id, name: call.name, text: text, isError: error)
        }
        if call.name == FetchURLTool.toolName, let fetch,
            let url = MCPToolHost.arguments(from: call.argumentsJSON)?["url"]?.string, !url.isEmpty {
            var forwarded = fetch.match.extra
            forwarded[fetch.match.queryKey] = .string(url)
            let client = fetch.client
            let toolName = fetch.match.tool.name
            let arguments: JSONValue = .object(forwarded)
            let timeout = searchTimeout
            let answer = try? await withDeadline(timeout) { try await client.callTool(name: toolName, arguments: arguments) }
            if Task.isCancelled { return result("The tool call was cancelled.", error: true) }
            if let answer, !answer.isError, !answer.text.isEmpty { return result(MCPToolHost.clip(answer.text), error: false) }
            // The scrape failed or came back empty: read the page on the device instead.
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
