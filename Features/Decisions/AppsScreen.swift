import SwiftData
import SwiftUI

/// Where the Apps stack can go. Every app and the custom decision share the one runner screen.
enum AppsDestination: Hashable { case runner, extract }

/// Sheet wrapper: the Apps list in its own navigation stack with a Close button and the Recent list one tap away.
struct AppsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Environment(ShellModel.self) private var shell
    @State private var path: [AppsDestination] = []
    @State private var showsRecent = false

    var body: some View {
        NavigationStack(path: $path) {
            AppsScreen(open: open, openExtract: { path = [.extract] }, showsRecent: $showsRecent)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                }
                .navigationDestination(for: AppsDestination.self) { destination in
                    switch destination {
                    case .runner: DecisionRunnerScreen(showsRecent: $showsRecent)
                    case .extract: ExtractScreen()
                    }
                }
        }
        .sheet(isPresented: $showsRecent) {
            DecisionRecentList { path = [.runner] }
        }
        .task {
            let store = app.decisions
            store.attach(context)
            store.loadApps()
            if let text = shell.takeDecisionDraft() {
                store.startCustom(state: text)
                path = [.runner]
            }
            await store.loadModels()
        }
    }

    private func open(_ tile: AppTile) {
        let store = app.decisions
        switch tile.target {
        case .decision(let id): store.start(store.apps.first { $0.id == id })
        case .custom: store.start(nil)
        }
        path = [.runner]
    }
}

/// The short list of apps. Each tile opens straight into "paste or snap, then Run".
struct AppsScreen: View {
    @Environment(AppState.self) private var app
    var open: (AppTile) -> Void
    var openExtract: () -> Void
    @Binding var showsRecent: Bool

    var body: some View {
        let store = app.decisions
        List {
            if let error = store.appsError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            ForEach(DecisionAppsLogic.tiles(for: store.apps)) { tile in
                Button { open(tile) } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading) {
                                Text(tile.title).font(.headline)
                                Text(tile.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: tile.symbol)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("apps-tile-\(tile.id)")
            }
            // Not a decision: a photo, PDF or scan in, typed fields out. Its own section keeps the decision tiles as they were.
            Section {
                Button(action: openExtract) {
                    HStack {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Extract").font(.headline)
                                Text("Fields from a receipt, bill, invoice or email").font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                        Spacer()
                        Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("apps-extract")
            }
        }
        .navigationTitle("Apps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsRecent = true } label: { Label("Recent", systemImage: "clock.arrow.circlepath") }
                    .accessibilityIdentifier("apps-recent")
            }
        }
    }
}
