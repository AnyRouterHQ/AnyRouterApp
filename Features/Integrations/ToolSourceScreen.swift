import SwiftUI

/// One source: what it is, who receives what its tools send, its tools with a switch each, and removal for custom servers.
struct ToolSourceScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let source: ToolSource
    @State private var confirmsRemove = false
    @State private var checkMessage: String?
    @State private var checkFailed = false
    @State private var isChecking = false
    @State private var forgotAgreement = false

    private var store: IntegrationsStore { app.integrations }
    private var modelSource: ModelSource? { app.models.selected?.source }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { app.tools.isOn(source, modelSource: modelSource) },
                    set: { app.tools.setSource(source, on: $0) })
                ) {
                    ListRow(source.title, subtitle: source.subtitle) { ToolSourceIcon(icon: source.icon) }
                }
            }
            if let server = source.server { connection(server) }
            toolsSection
            if source.group == .custom {
                Section {
                    Button("Remove server", role: .destructive) { confirmsRemove = true }
                }
            }
        }
        .formSwitches()
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove \(source.title)?", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let server = source.server { store.removeServer(server) }
                dismiss()
            }
        } message: {
            Text("Its saved token is deleted from this device.")
        }
    }

    // MARK: Connection

    @ViewBuilder
    private func connection(_ server: MCPServer) -> some View {
        if let recipient = source.recipient {
            Section {
                LabeledContent("Service", value: recipient.site)
                Button(isChecking ? "Checking…" : "Check connection") { check(server) }
                    .disabled(isChecking)
                if let checkMessage {
                    Text(checkMessage).foregroundStyle(checkFailed ? Color.red : Color.secondary)
                }
                if !forgotAgreement, app.integrations.permissions.hasAgreed(serverID: server.id) {
                    Button("Ask again before the next use") {
                        app.integrations.permissions.forgetAgreement(serverID: server.id)
                        forgotAgreement = true
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("\(recipient.name) receives what these tools send, such as your search words. No account or key is used, and your AnyRouter sign-in is never sent.")
            }
        } else {
            let state = store.state(for: server)
            Section("Connection") {
                LabeledContent("Server", value: server.url.host() ?? server.url.absoluteString)
                if case .failed(let message) = state.status {
                    Text(message).foregroundStyle(.red)
                } else {
                    Text(IntegrationsLogic.statusText(state.status, toolCount: state.tools.count))
                        .foregroundStyle(.secondary)
                }
                Button(state.status == .connecting ? "Connecting…" : "Reconnect") {
                    Task { await store.refresh(server) }
                }
                .disabled(state.status == .connecting)
            }
        }
    }

    private func check(_ server: MCPServer) {
        isChecking = true
        checkMessage = nil
        Task {
            switch await store.testConnection(urlString: server.url.absoluteString, token: "") {
            case .success(let summary):
                checkFailed = false
                checkMessage = "Connected to \(summary.serverName)."
            case .failure(let error):
                checkFailed = true
                checkMessage = error.localizedDescription
            }
            isChecking = false
        }
    }

    // MARK: Tools

    @ViewBuilder
    private var toolsSection: some View {
        switch source.group {
        case .onDevice:
            Section {
                ForEach(app.tools.tools.filter { $0.source == .builtIn && $0.name != WebSearchBinding.name }) { tool in
                    Toggle(isOn: Binding(
                        get: { app.tools.isBuiltInEnabled(tool.name) },
                        set: { app.tools.setBuiltIn(tool.name, enabled: $0) })
                    ) {
                        ListRow(tool.title, subtitle: tool.description) {
                            ToolSourceIcon(icon: .symbol(ToolSourceCatalog.symbol(forTool: tool.name)))
                        }
                    }
                }
            } header: {
                Text("Tools")
            } footer: {
                Text("Turned-off tools are never offered to the model.")
            }
        case .web:
            if let server = source.server {
                Section {
                    ForEach(source.tools, id: \.name) { pin in
                        let tool = pin.mcpTool
                        Toggle(isOn: Binding(
                            get: { store.isEnabled(tool, on: server) },
                            set: { store.setEnabled($0, tool: tool, on: server) })
                        ) {
                            ListRow(pin.title, subtitle: pin.summary) { ToolSourceIcon(icon: .symbol(pin.symbol)) }
                        }
                    }
                } header: {
                    Text("Tools")
                } footer: {
                    Text("Turned-off tools are never offered to the model.")
                }
            }
        case .anyRouter, .custom:
            if let server = source.server { liveTools(server) }
        }
    }

    @ViewBuilder
    private func liveTools(_ server: MCPServer) -> some View {
        let state = store.state(for: server)
        let search = server.auth == .anyRouterSignIn ? app.tools.tools.first(where: { $0.name == WebSearchBinding.name }) : nil
        if !state.tools.isEmpty || search != nil {
            Section {
                if let search {
                    Toggle(isOn: Binding(
                        get: { app.tools.isBuiltInEnabled(search.name) },
                        set: { app.tools.setBuiltIn(search.name, enabled: $0) })
                    ) {
                        ListRow(search.title, subtitle: search.description) {
                            ToolSourceIcon(icon: .symbol(ToolSourceCatalog.symbol(forTool: search.name)))
                        }
                    }
                }
                if server.auth == .anyRouterSignIn {
                    Toggle(isOn: Binding(
                        get: { app.tools.isBuiltInEnabled(DecideTool.toolName) },
                        set: { app.tools.setBuiltIn(DecideTool.toolName, enabled: $0) })
                    ) {
                        ListRow("Decide", subtitle: "Ask a decision model about a text. Uses your AnyRouter credits; chats with a model on this device ask first.") {
                            ToolSourceIcon(icon: .symbol(ToolSourceCatalog.symbol(forTool: DecideTool.toolName)))
                        }
                    }
                    .accessibilityIdentifier("tools.decide")
                    Toggle(isOn: Binding(
                        get: { app.tools.isBuiltInEnabled(SubagentLogic.toolName) },
                        set: { app.tools.setBuiltIn(SubagentLogic.toolName, enabled: $0) })
                    ) {
                        ListRow("Subagents", subtitle: "Let a cloud model hand a research task to a helper on the same model. Its tokens count in the reply.") {
                            ToolSourceIcon(icon: .symbol("person.2"))
                        }
                    }
                    .accessibilityIdentifier("tools.subagents")
                }
                ForEach(state.tools) { tool in
                    Toggle(isOn: Binding(
                        get: { store.isEnabled(tool, on: server) },
                        set: { store.setEnabled($0, tool: tool, on: server) })
                    ) {
                        ListRow(tool.displayName, subtitle: subtitle(for: tool, on: server)) {
                            ToolSourceIcon(icon: .symbol(ToolSourceCatalog.symbol(forTool: tool.name)))
                        }
                    }
                }
            } header: {
                Text("Tools")
            } footer: {
                Text("Turned-off tools are never offered to the model.")
            }
        }
    }

    private func subtitle(for tool: MCPTool, on server: MCPServer) -> String {
        let id = IntegrationsLogic.toolKey(serverID: server.id, toolName: tool.name)
        let needsApproval = app.tools.tools.first { $0.id == id }?.needsApproval ?? false
        let description = tool.description ?? ""
        return needsApproval ? "Needs approval. " + description : description
    }
}
