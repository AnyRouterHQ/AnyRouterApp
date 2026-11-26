import SwiftUI

/// Settings › AnyRouter Models: the cloud models this account can use. Tap for details, long-press to make one the default.
struct AnyRouterModelsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    @State private var detailModel: ModelDescriptor?
    @State private var routerDetail: ModelDescriptor?
    @State private var signInError: String?

    private var list: CloudList {
        CloudListLogic.arrange(
            models: models.models, query: "", sort: .topUsage, usageRank: models.usageRank,
            showUnusable: false, picks: [], filter: ModelFilter())
    }

    var body: some View {
        List {
            if let note = models.defaultNote {
                Section { Label(note, systemImage: "exclamationmark.triangle") }
            }
            Section {
                ForEach(list.rest) { row($0) }
            }
        }
        .accessibilityIdentifier("anyrouter.list")
        .overlay { stateOverlay }
        .navigationDestination(item: $detailModel) { model in
            CloudModelDetailView(model: model, usage: models.weeklyUsage[model.wireID], onShowRouting: showRouting(for: model))
        }
        .sheet(item: $routerDetail) { RouterDetailSheet(router: $0) }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch app.account.state {
        case .signedOut:
            ContentUnavailableView {
                Label("Sign in to use cloud models", systemImage: "cloud")
            } description: {
                Text("AnyRouter picks the best model for each message.")
                if let signInError { Text(signInError).foregroundStyle(.red) }
            } actions: {
                Button("Sign in with AnyRouter") { signIn() }.buttonStyle(.borderedProminent)
            }
        case .signingIn:
            ProgressView("Signing in…")
        case .signedIn:
            if list.isEmpty { ContentUnavailableView("No cloud models", systemImage: "cloud") }
        }
    }

    private func row(_ model: ModelDescriptor) -> some View {
        HStack(spacing: 8) {
            Button { detailModel = model } label: {
                ModelRowView(row: PickerRow.make(model), isCurrent: false)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            if models.selected?.id == model.id { DefaultBadge() }
        }
        .contextMenu {
            Button("Set as Default", systemImage: "star") { models.select(model) }
        }
    }

    /// A router's detail screen can open the list of models it picks from.
    private func showRouting(for model: ModelDescriptor) -> (() -> Void)? {
        guard model.isRouter, (model.cloud?.memberCount ?? 0) > 0 else { return nil }
        return { routerDetail = model }
    }

    private func signIn() {
        signInError = nil
        Task {
            do {
                try await app.account.signIn()
                await models.refresh()
            } catch {
                signInError = error.localizedDescription
            }
        }
    }
}
