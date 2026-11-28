import SwiftUI

/// Settings › AnyRouter Models: the cloud models this account can use. Search, sort and filter; swipe to star or hide;
/// long-press to make one the default. Starred models lead here and in the model picker.
struct AnyRouterModelsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    @State private var query = ""
    @State private var sort = PickerSort.topUsage
    @State private var filter = ModelFilter()
    @State private var showsFilters = false
    @State private var detailModel: ModelDescriptor?
    @State private var routerDetail: ModelDescriptor?
    @State private var signInError: String?

    private var signedIn: Bool { app.account.state.isSignedIn }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var list: CloudList {
        CloudListLogic.arrange(
            models: models.models, query: query, sort: sort, usageRank: models.usageRank,
            showUnusable: signedIn, picks: [], filter: filter, prefs: models.cloudPrefs)
    }

    private var hiddenCount: Int { models.cloudPrefs.hiddenModels(in: models.models).count }

    var body: some View {
        let list = list
        List {
            if let note = models.defaultNote {
                Section { Label(note, systemImage: "exclamationmark.triangle") }
            }
            if let failure = models.loadFailures[.anyrouter], !models.isLoading, !list.isEmpty {
                CloudListStaleNotice(message: failure) { Task { await models.refresh() } }
            }
            if !list.starred.isEmpty {
                Section("Starred") { ForEach(list.starred) { row($0) } }
            }
            if !list.rest.isEmpty {
                Section {
                    ForEach(list.rest) { row($0) }
                } header: {
                    if !list.starred.isEmpty { Text("All models") }
                }
            }
            if hiddenCount > 0 && !isSearching {
                Section {
                    NavigationLink {
                        HiddenModelsScreen()
                    } label: {
                        Text("Hidden (\(hiddenCount))")
                    }
                    .accessibilityIdentifier("anyrouter.hidden")
                }
            }
        }
        .accessibilityIdentifier("anyrouter.list")
        .overlay { stateOverlay(list) }
        .searchable(text: $query, prompt: "Search models")
        .toolbar {
            if signedIn {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(PickerSort.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("anyrouter.sort")
                    Button { showsFilters = true } label: {
                        Label("Filter", systemImage: filter.isActive
                            ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityValue(filter.isActive ? "\(filter.activeCount) active" : "none")
                    .accessibilityIdentifier("anyrouter.filter")
                }
            }
        }
        .navigationDestination(item: $detailModel) { model in
            CloudModelDetailView(model: model, usage: models.weeklyUsage[model.wireID], onShowRouting: showRouting(for: model))
        }
        .sheet(item: $routerDetail) { RouterDetailSheet(router: $0) }
        .navigationDestination(isPresented: $showsFilters) {
            ModelFilterForm(
                tab: .anyrouter, cloud: $filter, local: .constant(LocalFilter()),
                providers: ModelFilter.providers(in: models.models))
        }
    }

    @ViewBuilder
    private func stateOverlay(_ list: CloudList) -> some View {
        switch app.account.state {
        case .signedOut:
            ContentUnavailableView {
                Label("Sign in to use cloud models", systemImage: "cloud")
            } description: {
                Text("AnyRouter picks the best model for each message.")
                if let signInError { SignInFailureNotice(raw: signInError) }
            } actions: {
                Button { signIn() } label: { Text("Sign in with AnyRouter").prominentLabel() }.buttonStyle(.borderedProminent)
            }
        case .signingIn:
            ProgressView("Signing in…")
        case .signedIn:
            if list.isEmpty {
                if isSearching || filter.isActive {
                    ContentUnavailableView {
                        Label(isSearching ? "No results for “\(query)”" : "No matching models", systemImage: "magnifyingglass")
                    } description: {
                        Text(filter.isActive ? "Try a different search or clear the filters." : "Check the spelling or try a new search.")
                    } actions: {
                        if filter.isActive { Button("Clear filters") { filter = ModelFilter() }.buttonStyle(.bordered) }
                    }
                } else {
                    CloudListEmptyState(
                        reason: CloudEmptyReason.reason(
                            models: models.models, failure: models.loadFailures[.anyrouter], isLoading: models.isLoading),
                        retry: { Task { await models.refresh() } })
                }
            }
        }
    }

    private func row(_ model: ModelDescriptor) -> some View {
        let starred = models.cloudPrefs.isStarred(model)
        return HStack(spacing: 8) {
            Button { detailModel = model } label: {
                ModelRowView(
                    row: PickerRow.make(model, usage: CloudListLogic.rowUsage(of: model, sort: sort, in: models.weeklyUsage)),
                    isCurrent: false)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            if models.selected?.id == model.id { DefaultBadge() }
        }
        .swipeActions(edge: .leading) {
            Button { models.toggleStar(model) } label: {
                Label(starred ? "Unstar" : "Star", systemImage: starred ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button { models.hide(model) } label: { Label("Hide", systemImage: "eye.slash") }
                .tint(.gray)
        }
        .contextMenu {
            Button("Set as Default", systemImage: "star") { models.select(model) }
                .disabled(!model.isInstalled)
            Button(starred ? "Unstar" : "Star", systemImage: starred ? "star.slash" : "star") { models.toggleStar(model) }
            Button("Hide", systemImage: "eye.slash") { models.hide(model) }
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

/// The models the person hid, with a way back.
struct HiddenModelsScreen: View {
    @Environment(ModelStore.self) private var models

    private var hidden: [ModelDescriptor] { models.cloudPrefs.hiddenModels(in: models.models) }

    var body: some View {
        List {
            Section {
                ForEach(hidden) { model in
                    HStack(spacing: 8) {
                        ModelRowView(row: PickerRow.make(model), isCurrent: false)
                        Button("Show") { models.unhide(model) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Show \(model.shortName)")
                    }
                    .swipeActions(edge: .trailing) {
                        Button { models.unhide(model) } label: { Label("Show", systemImage: "eye") }
                            .tint(ARPalette.tint)
                    }
                }
            } footer: {
                if !hidden.isEmpty { Text("Hidden models stay out of the model lists. Search still finds them.") }
            }
        }
        .accessibilityIdentifier("anyrouter.hidden.list")
        .navigationTitle("Hidden")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if hidden.isEmpty { ContentUnavailableView("Nothing hidden", systemImage: "eye") }
        }
    }
}
