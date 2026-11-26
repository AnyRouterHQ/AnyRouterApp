import SwiftUI

/// Settings › Integrations: the AnyRouter tool server, built-in tools and custom MCP servers.
/// Pushed from the Settings list, so it relies on that NavigationStack.
struct IntegrationsSettingsView: View {
    @Environment(AppState.self) private var app

    @State private var showsAdd = false

    private var store: IntegrationsStore { app.integrations }

    private var builtInTools: [RegisteredTool] { app.tools.tools.filter { $0.source == .builtIn } }

    var body: some View {
        Form {
            Section("AnyRouter") {
                IntegrationServerRow(server: .anyRouter)
            }
            Section {
                ForEach(builtInTools) { tool in
                    Toggle(isOn: Binding(
                        get: { app.tools.isBuiltInEnabled(tool.name) },
                        set: { app.tools.setBuiltIn(tool.name, enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.title)
                            Text(tool.description).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Built-in tools")
            } footer: {
                Text("Turned-off tools are never offered to the model.")
            }
            Section {
                ForEach(store.customServers) { IntegrationServerRow(server: $0) }
                    .onDelete { offsets in
                        let doomed = offsets.map { store.customServers[$0] }
                        doomed.forEach { store.removeServer($0) }
                    }
                Button("Add MCP server") { showsAdd = true }
            } header: {
                Text("Custom servers")
            } footer: {
                if store.customServers.isEmpty { Text("Add a remote MCP server to give chats more tools.") }
            }
        }
        .navigationDestination(for: MCPServer.self) { IntegrationServerScreen(server: $0) }
        .sheet(isPresented: $showsAdd) { AddMCPServerSheet() }
        .task { await store.refreshAll() }
    }
}

/// One server: name and status line, opens its tool list.
private struct IntegrationServerRow: View {
    @Environment(AppState.self) private var app
    let server: MCPServer

    var body: some View {
        let state = app.integrations.state(for: server)
        NavigationLink(value: server) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                    Text(IntegrationsLogic.statusText(state.status, toolCount: state.tools.count))
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            } icon: {
                if server.auth == .anyRouterSignIn {
                    ARLogoMark(size: 22)
                } else {
                    Image(systemName: "server.rack")
                }
            }
        }
    }
}

/// Status, the live tool list with switches, and removal for custom servers.
struct IntegrationServerScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let server: MCPServer
    @State private var confirmsRemove = false

    private var store: IntegrationsStore { app.integrations }

    var body: some View {
        let state = store.state(for: server)
        Form {
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
            if !state.tools.isEmpty {
                Section {
                    ForEach(state.tools) { toolRow($0) }
                } header: {
                    Text("Tools")
                } footer: {
                    Text("Turned-off tools are never offered to the model.")
                }
            }
            if server.id != MCPServer.anyRouter.id {
                Section {
                    Button("Remove server", role: .destructive) { confirmsRemove = true }
                }
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove \(server.name)?", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                store.removeServer(server)
                dismiss()
            }
        } message: {
            Text("Its saved token is deleted from this device.")
        }
    }

    private func needsApproval(_ tool: MCPTool) -> Bool {
        let id = IntegrationsLogic.toolKey(serverID: server.id, toolName: tool.name)
        return app.tools.tools.first { $0.id == id }?.needsApproval ?? false
    }

    private func toolRow(_ tool: MCPTool) -> some View {
        Toggle(isOn: Binding(
            get: { store.isEnabled(tool, on: server) },
            set: { store.setEnabled($0, tool: tool, on: server) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName)
                if needsApproval(tool) {
                    Text("Needs approval").font(.footnote).foregroundStyle(.secondary)
                }
                if let description = tool.description, !description.isEmpty {
                    Text(description).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
                }
            }
        }
    }
}

/// URL and optional bearer token for a custom server, with a connection test.
struct AddMCPServerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var urlText = ""
    @State private var token = ""
    @State private var message: String?
    @State private var isError = false
    @State private var isBusy = false

    private var canSubmit: Bool { !urlText.trimmingCharacters(in: .whitespaces).isEmpty && !isBusy }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $name)
                    TextField("https://example.com/mcp", text: $urlText)
                        .keyboardType(.URL)
                    SecureField("Bearer token (optional)", text: $token)
                } header: {
                    Text("Server")
                } footer: {
                    Text("The token is stored in the Keychain on this device and sent only to this server.")
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Section {
                    Button(isBusy ? "Working…" : "Test connection") { test() }
                        .disabled(!canSubmit)
                    if let message {
                        Text(message).foregroundStyle(isError ? Color.red : Color.secondary)
                    }
                }
            }
            .navigationTitle("Add MCP server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.disabled(!canSubmit)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func test() {
        isBusy = true
        message = nil
        Task {
            switch await app.integrations.testConnection(urlString: urlText, token: token) {
            case .success(let summary):
                isError = false
                message = "Connected to \(summary.serverName). \(summary.toolCount) tools found."
            case .failure(let error):
                isError = true
                message = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func add() {
        isBusy = true
        message = nil
        Task {
            switch await app.integrations.testConnection(urlString: urlText, token: token) {
            case .success:
                do {
                    let server = try app.integrations.addServer(name: name, urlString: urlText, token: token)
                    isBusy = false
                    dismiss()
                    await app.integrations.refresh(server)
                    return
                } catch {
                    isError = true
                    message = error.localizedDescription
                }
            case .failure(let error):
                isError = true
                message = "Not added: \(error.localizedDescription)"
            }
            isBusy = false
        }
    }
}
