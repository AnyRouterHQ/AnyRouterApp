import SwiftUI

/// Settings › Integrations: where the model's tools come from, in four sections (on device, web, AnyRouter, custom
/// servers). Every source is a row with an icon, a one-line subtitle and a switch; its page lists its tools.
/// Pushed from the Settings list, so it relies on that NavigationStack.
struct IntegrationsSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings

    @State private var showsAdd = false
    @State private var detail: ToolSource?

    private var store: IntegrationsStore { app.integrations }

    var body: some View {
        List {
            ForEach(ToolSource.Group.allCases) { group in
                let sources = app.tools.sources.filter { $0.group == group }
                if group == .custom {
                    customSection(sources)
                } else if !sources.isEmpty {
                    Section {
                        ForEach(sources) { source in ToolSourceRow(source: source) { detail = $0 } }
                    } header: {
                        Text(group.title)
                    } footer: {
                        footer(for: group)
                    }
                }
            }
            onDeviceModelsSection
        }
        // The model list carries the tools capability, so it is read again when the switch moves.
        .onChange(of: settings.onDeviceTools) { Task { await app.models.refresh() } }
        .navigationDestination(item: $detail) { ToolSourceScreen(source: $0) }
        .sheet(isPresented: $showsAdd) { AddMCPServerSheet().formSwitches() }
        .task { await store.refreshAll() }
    }

    private var onDeviceModelsSection: some View {
        Section {
            Toggle(isOn: Bindable(settings).onDeviceTools) {
                ListRow(
                    "Tools on this device's models",
                    subtitle: "Qwen, Llama 3 and Gemma models can call the tools above. Uses part of their small context."
                ) { ToolSourceIcon(icon: .symbol("cpu")) }
            }
            .formSwitches()
            .accessibilityIdentifier("tools.on-device-models")
        } footer: {
            Text("These models get four tools at most, so the list fits their small context. Calls from them are not yet checked on a device.")
        }
    }

    private func customSection(_ sources: [ToolSource]) -> some View {
        Section {
            ForEach(sources) { source in ToolSourceRow(source: source) { detail = $0 } }
                .onDelete { offsets in
                    let doomed = offsets.compactMap { sources[$0].server }
                    doomed.forEach { store.removeServer($0) }
                }
            Button("Add MCP server") { showsAdd = true }
        } header: {
            Text(ToolSource.Group.custom.title)
        } footer: {
            if sources.isEmpty { Text("Add a remote MCP server to give chats more tools.") }
        }
    }

    @ViewBuilder
    private func footer(for group: ToolSource.Group) -> some View {
        switch group {
        case .web:
            Text("A web tool sends what it needs, such as your search words, to the service named on its row. Your AnyRouter sign-in is never sent to them.")
        case .onDevice:
            Text("Turned-off tools are never offered to the model.")
        default:
            EmptyView()
        }
    }
}

/// A source as a row: icon, name, one line about it, a switch, and a button to its page.
private struct ToolSourceRow: View {
    @Environment(AppState.self) private var app
    let source: ToolSource
    let open: (ToolSource) -> Void

    private var modelSource: ModelSource? { app.models.selected?.source }

    var body: some View {
        let signedOut = source.requiresSignIn && app.integrations.state(for: .anyRouter).status == .needsSignIn
        HStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { app.tools.isOn(source, modelSource: modelSource) },
                set: { app.tools.setSource(source, on: $0) })
            ) {
                ListRow(source.title, subtitle: signedOut ? "Sign in to connect" : source.subtitle) {
                    ToolSourceIcon(icon: source.icon)
                }
            }
            .disabled(signedOut)
            .formSwitches()
            .accessibilityIdentifier("tools.source.\(source.id)")
            Button { open(source) } label: {
                Label("Tools of \(source.title)", systemImage: "chevron.right").labelStyle(.iconOnly)
                    // The HIG minimum hit area, inside the label so the button itself is 44 pt.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("tools.detail.\(source.id)")
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
        .presentationSizing(.form)
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
