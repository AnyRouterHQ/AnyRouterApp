import Foundation

/// What the user is asked before a tool that is not read-only runs.
struct ToolApprovalRequest: Sendable, Equatable {
    var serverName: String
    var spec: ToolSpec
    var call: ToolCall
}

/// Asks the user. The chat UI implements this with a sheet; it suspends until the user decides.
protocol ToolApproving: Sendable {
    func decide(_ request: ToolApprovalRequest) async -> ToolDecision
}

/// "Always allow" choices, kept per server and tool. UserDefaults is thread-safe, so the host can read it off the main actor.
final class ToolPermissionStore: @unchecked Sendable {
    private static let key = "integrations.alwaysAllow"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isAlwaysAllowed(serverID: String, toolName: String) -> Bool {
        stored.contains(IntegrationsLogic.toolKey(serverID: serverID, toolName: toolName))
    }

    func allow(serverID: String, toolName: String) {
        update { $0.insert(IntegrationsLogic.toolKey(serverID: serverID, toolName: toolName)) }
    }

    func revoke(serverID: String, toolName: String) {
        update { $0.remove(IntegrationsLogic.toolKey(serverID: serverID, toolName: toolName)) }
    }

    func revokeAll(serverID: String) {
        update { set in set = set.filter { !$0.hasPrefix(serverID + "/") } }
    }

    private var stored: Set<String> { Set(defaults.stringArray(forKey: Self.key) ?? []) }

    private func update(_ change: (inout Set<String>) -> Void) {
        var set = stored
        change(&set)
        defaults.set(Array(set).sorted(), forKey: Self.key)
    }
}

/// The tools of the connected MCP servers that the user left on, as one `ToolHost`.
struct MCPToolHost: ToolHost {
    struct Entry: Sendable {
        var server: MCPServer
        var tool: MCPTool
        var spec: ToolSpec
        var client: MCPClient
    }

    /// Tool results longer than this are cut so one page scrape cannot fill the model's context.
    static let maxResultCharacters = 20_000

    let specs: [ToolSpec]
    private let entries: [String: Entry]
    private let approver: any ToolApproving
    private let permissions: ToolPermissionStore
    private let timeout: Double

    /// `reserved` are names other tool sources already use (the built-in tools); an MCP tool with such a name gets its server name in front.
    init(
        enabled: [(server: MCPServer, tool: MCPTool)],
        client: (MCPServer) -> MCPClient,
        approver: any ToolApproving,
        permissions: ToolPermissionStore,
        reserved: Set<String> = [],
        timeout: Double = 45
    ) {
        self.timeout = timeout
        let names = Self.uniqueNames(for: enabled, reserved: reserved)
        var entries: [String: Entry] = [:]
        var specs: [ToolSpec] = []
        for (index, item) in enabled.enumerated() {
            let spec = ToolSpec(
                name: names[index],
                title: item.tool.title ?? item.tool.annotations?.title,
                description: item.tool.description ?? item.tool.displayName,
                inputSchemaJSON: item.tool.inputSchema.jsonString(),
                // A custom server's read-only hint is only a hint: it must not skip the user's approval.
                isReadOnly: item.server.skipsApproval(item.tool)
            )
            specs.append(spec)
            entries[spec.name] = Entry(server: item.server, tool: item.tool, spec: spec, client: client(item.server))
        }
        self.specs = specs
        self.entries = entries
        self.approver = approver
        self.permissions = permissions
    }

    func execute(_ call: ToolCall) async -> ToolResult {
        func failure(_ text: String) -> ToolResult {
            ToolResult(callID: call.id, name: call.name, text: text, isError: true)
        }
        guard let entry = entries[call.name] else { return failure("Unknown tool: \(call.name).") }
        guard let arguments = Self.arguments(from: call.argumentsJSON) else {
            return failure("The arguments are not a JSON object.")
        }

        if !entry.spec.isReadOnly,
            !permissions.isAlwaysAllowed(serverID: entry.server.id, toolName: entry.tool.name) {
            let request = ToolApprovalRequest(serverName: entry.server.name, spec: entry.spec, call: call)
            switch await approver.decide(request) {
            case .deny: return failure("The user did not allow this tool call.")
            case .alwaysAllow: permissions.allow(serverID: entry.server.id, toolName: entry.tool.name)
            case .allowOnce: break
            }
        }

        do {
            let client = entry.client
            let toolName = entry.tool.name
            let timeout = timeout
            // The deadline starts after approval: waiting for the user does not count.
            let result = try await withDeadline(timeout) { try await client.callTool(name: toolName, arguments: arguments) }
            return ToolResult(callID: call.id, name: call.name, text: Self.clip(result.text), isError: result.isError)
        } catch is CancellationError {
            return failure("The tool call was cancelled.")
        } catch {
            return failure(error.localizedDescription)
        }
    }

    // MARK: Helpers

    /// Empty text means no arguments. Anything but a JSON object is rejected.
    static func arguments(from json: String) -> JSONValue? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .object([:]) }
        guard let value = JSONValue.parse(trimmed), value.object != nil else { return nil }
        return value
    }

    static func clip(_ text: String) -> String {
        guard text.count > maxResultCharacters else { return text }
        return String(text.prefix(maxResultCharacters)) + "\n[Result cut at \(maxResultCharacters) characters.]"
    }

    /// Model APIs want `[A-Za-z0-9_-]{1,64}` and unique names. Two servers may both have `search`; then the
    /// server name is put in front of the tool name.
    static func uniqueNames(for enabled: [(server: MCPServer, tool: MCPTool)], reserved: Set<String> = []) -> [String] {
        let plain = enabled.map { sanitize($0.tool.name) }
        let counts = Dictionary(plain.map { ($0, 1) }, uniquingKeysWith: +)
        var used = reserved
        return enabled.enumerated().map { index, item in
            let alone = counts[plain[index]] == 1 && !reserved.contains(plain[index])
            var name = alone ? plain[index] : sanitize("\(item.server.name)__\(item.tool.name)")
            var suffix = 2
            let base = name.prefix(60)
            while used.contains(name) {
                name = "\(base)_\(suffix)"
                suffix += 1
            }
            used.insert(name)
            return name
        }
    }

    static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let mapped = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let trimmed = String(mapped.prefix(64))
        return trimmed.isEmpty ? "tool" : trimmed
    }
}
