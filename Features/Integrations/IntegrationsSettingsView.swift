import SwiftUI

/// Settings › Integrations: the AnyRouter tool server, custom MCP servers, and per-tool switches.
/// Pushed from the Settings list, so it relies on that NavigationStack.
struct IntegrationsSettingsView: View {
    @Environment(AppState.self) private var app

    @State private var showsAdd = false

    private var store: IntegrationsStore { app.integrations }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsGroup("AnyRouter") {
                    IntegrationServerRow(server: .anyRouter)
                }
                SettingsGroup("Custom servers") {
                    if store.customServers.isEmpty {
                        SettingsText("Add a remote MCP server to give chats more tools.")
                    }
                    ForEach(store.customServers) { server in
                        IntegrationServerRow(server: server)
                    }
                    Button("Add MCP server") { showsAdd = true }.buttonStyle(.arSecondary)
                }
            }
            .frame(maxWidth: ARTheme.contentMaxWidth)
            .padding(.horizontal, ARTheme.pagePadding)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(ARColor.background.ignoresSafeArea())
        .navigationDestination(for: MCPServer.self) { server in
            IntegrationServerScreen(server: server)
        }
        .sheet(isPresented: $showsAdd) { AddMCPServerSheet() }
        .task { await store.refreshAll() }
        .onChange(of: app.account.state) {
            Task { await store.refresh(.anyRouter) }
        }
    }
}

/// One server card: name, address, status, tool count.
private struct IntegrationServerRow: View {
    @Environment(AppState.self) private var app
    let server: MCPServer

    var body: some View {
        let state = app.integrations.state(for: server)
        NavigationLink(value: server) {
            HStack(spacing: 12) {
                Image(systemName: server.auth == .anyRouterSignIn ? "cloud" : "server.rack")
                    .frame(width: 22)
                    .foregroundStyle(ARColor.mutedForeground)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name).font(.arBase).foregroundStyle(ARColor.foreground)
                    Text(server.url.host() ?? server.url.absoluteString)
                        .font(.arXS).foregroundStyle(ARColor.mutedForeground).lineLimit(1)
                }
                Spacer()
                IntegrationStatusChip(status: state.status, toolCount: state.tools.count)
                Image(systemName: "chevron.right").font(.arXS).foregroundStyle(ARColor.mutedForeground)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct IntegrationStatusChip: View {
    let status: IntegrationsStore.Status
    let toolCount: Int

    var body: some View {
        switch status {
        case .idle: ARChip(text: "Not connected")
        case .connecting: ARChip(text: "Connecting")
        case .needsSignIn: ARChip(text: "Sign in", tint: ARColor.accent)
        case .connected: ARChip(text: toolCount == 1 ? "1 tool" : "\(toolCount) tools", tint: ARColor.accent)
        case .failed: ARChip(text: "Error", tint: ARColor.destructive)
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
        ScrollView {
            VStack(spacing: 20) {
                SettingsGroup("Connection") {
                    HStack(spacing: 12) {
                        Image(systemName: "link").frame(width: 22).foregroundStyle(ARColor.mutedForeground)
                        Text("Server").font(.arBase).foregroundStyle(ARColor.foreground)
                        Spacer()
                        Text(server.url.host() ?? "").font(.arSM).foregroundStyle(ARColor.mutedForeground).lineLimit(1)
                    }
                    statusBody(state)
                    Button(state.status == .connecting ? "Connecting…" : "Reconnect") {
                        Task { await store.refresh(server) }
                    }
                    .buttonStyle(.arSecondary)
                    .disabled(state.status == .connecting)
                }
                if !state.tools.isEmpty {
                    SettingsGroup("Tools") {
                        SettingsText("Turned-off tools are never offered to the model.")
                        ForEach(state.tools) { tool in
                            toolRow(tool)
                        }
                    }
                }
                if server.id != MCPServer.anyRouter.id {
                    Button("Remove server") { confirmsRemove = true }.buttonStyle(.arDestructive)
                }
            }
            .frame(maxWidth: ARTheme.contentMaxWidth)
            .padding(.horizontal, ARTheme.pagePadding)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(ARColor.background.ignoresSafeArea())
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

    @ViewBuilder
    private func statusBody(_ state: IntegrationsStore.ServerState) -> some View {
        switch state.status {
        case .idle: SettingsText("Not connected yet.")
        case .connecting: HStack { ProgressView(); SettingsText("Connecting…") }
        case .needsSignIn: SettingsText("Sign in with AnyRouter in Settings to use these tools.")
        case .connected: SettingsText("Connected. \(state.tools.count) tools available.")
        case .failed(let message):
            Text(message).font(.arSM).foregroundStyle(ARColor.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toolRow(_ tool: MCPTool) -> some View {
        let binding = Binding(
            get: { store.isEnabled(tool, on: server) },
            set: { store.setEnabled($0, tool: tool, on: server) }
        )
        return Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tool.displayName).font(.arBase).foregroundStyle(ARColor.foreground)
                    if tool.isReadOnly { ARChip(text: "read-only") }
                }
                if tool.displayName != tool.name {
                    Text(tool.name).font(.arXS).foregroundStyle(ARColor.mutedForeground)
                }
                if let description = tool.description, !description.isEmpty {
                    Text(description).font(.arSM).foregroundStyle(ARColor.mutedForeground).lineLimit(4)
                }
            }
        }
        .tint(ARColor.accent)
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
            ScrollView {
                VStack(spacing: 20) {
                    SettingsGroup("Server") {
                        field("Name (optional)", text: $name)
                        field("https://example.com/mcp", text: $urlText, url: true)
                        SecureField("Bearer token (optional)", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(ARColor.input.opacity(0.5), in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
                        SettingsText("The token is stored in the Keychain on this device and sent only to this server.")
                    }
                    if let message {
                        if isError {
                            Text(message).font(.arSM).foregroundStyle(ARColor.destructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            SettingsText(message)
                        }
                    }
                    Button(isBusy ? "Working…" : "Test connection") { test() }
                        .buttonStyle(.arSecondary)
                        .disabled(!canSubmit)
                    Button("Add server") { add() }
                        .buttonStyle(.arFilled)
                        .disabled(!canSubmit)
                }
                .padding(.horizontal, ARTheme.pagePadding)
                .padding(.bottom, 24)
            }
            .background(ARColor.background.ignoresSafeArea())
            .navigationTitle("Add MCP server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func field(_ prompt: String, text: Binding<String>, url: Bool = false) -> some View {
        TextField(prompt, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(url ? .URL : .default)
            .padding(10)
            .background(ARColor.input.opacity(0.5), in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
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
