import SwiftData
import SwiftUI

/// Settings as a native drill-down: a sheet with a navigation stack and a grouped inset list.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShellModel.self) private var shell
    @State private var path: [SettingsDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            SettingsList()
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
                .navigationDestination(for: SettingsDestination.self) { destination in
                    SettingsDestinationView(destination: destination)
                }
        }
        .onAppear {
            guard let destination = shell.settingsDestination else { return }
            shell.settingsDestination = nil
            path = [destination]
        }
    }
}

private struct SettingsList: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    var body: some View {
        List {
            Section { AccountCard() }
            ForEach(SettingsDestination.Group.allCases, id: \.self) { group in
                Section {
                    ForEach(group.destinations, id: \.self) { destination in
                        NavigationLink(value: destination) {
                            ListRow(destination.title, subtitle: subtitle(for: destination)) {
                                SettingsIcon(glyph: destination.glyph, color: destination.tileColor)
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    if group == .models, let note = models.defaultNote { Text(note) }
                }
            }
        }
    }

    /// The second line of a row that has one: how much is installed, which cloud model is the default.
    private func subtitle(for destination: SettingsDestination) -> String? {
        switch destination {
        case .localModels:
            let installed = LocalModelsLogic.installed(app.hub.catalog, state: { app.hub.downloadState(for: $0) })
            let storage = LocalModelsLogic.storage(installed: installed, freeBytes: nil)
            return SettingsLogic.localModelsSubtitle(installedCount: storage.modelCount, usedBytes: storage.usedBytes)
        case .anyRouterModels:
            let selected = models.selected
            return SettingsLogic.anyRouterModelsSubtitle(
                defaultName: selected?.source == .anyrouter ? selected?.shortName : nil,
                starredCount: models.cloudPrefs.starredCount(in: models.models))
        default:
            return nil
        }
    }
}

/// The single routing switch. Add a case to `SettingsDestination` and a branch here.
struct SettingsDestinationView: View {
    let destination: SettingsDestination

    var body: some View {
        Group {
            switch destination {
            case .localModels: LocalModelsScreen()
            case .anyRouterModels: AnyRouterModelsScreen()
            case .responseCustomization: ResponseCustomizationSettings()
            case .presets: PresetsSettingsView()
            case .integrations: IntegrationsSettingsView()
            case .chatBehavior: ChatBehaviorSettings()
            case .memory: MemorySettings()
            case .shortcuts: ShortcutsSettings()
            case .theme: ThemeSettings()
            case .about: AboutSettings()
            case .diagnostics: DiagnosticsSettings()
            case .privacy: PrivacySettings()
            case .terms: LegalPage(kind: .terms)
            case .licenses: LicensesSheet()
            }
        }
        .navigationTitle(destination.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
