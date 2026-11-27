import SwiftData
import SwiftUI
import UIKit

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
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    @State private var versionTaps = 0
    @State private var copiedDiagnostics = false

    var body: some View {
        @Bindable var settings = settings
        List {
            Section { AccountCard() }
            ForEach(SettingsDestination.Group.allCases, id: \.self) { group in
                Section {
                    ForEach(group.destinations, id: \.self) { destination in
                        NavigationLink(value: destination) {
                            LabeledContent {
                                if let subtitle = subtitle(for: destination) { Text(subtitle) }
                            } label: {
                                Label(destination.title, systemImage: destination.systemImage)
                            }
                        }
                    }
                    if group == .chat {
                        Toggle(isOn: $settings.showKeyboardOnLaunch) {
                            Label("Show keyboard on launch", systemImage: "keyboard")
                        }
                        .accessibilityIdentifier("settings-show-keyboard")
                        Picker(selection: $settings.newChatDelay) {
                            ForEach(NewChatDelay.allCases) { Text($0.title).tag($0) }
                        } label: {
                            Label("Start a new chat after", systemImage: "clock.arrow.circlepath")
                        }
                        .accessibilityIdentifier("settings-new-chat-after")                    }
                    if group == .about { versionRow }
                } header: {
                    Text(group.title)
                } footer: {
                    if group == .models, let note = models.defaultNote { Text(note) }
                    if group == .chat {
                        Text("The keyboard opens when you start the app. Leave the app for the time above and it opens on a new chat; a shorter break keeps your conversation.")
                    }
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

    private var versionRow: some View {
        Button {
            versionTaps += 1
            if versionTaps >= SettingsLogic.diagnosticsTapCount {
                versionTaps = 0
                UIPasteboard.general.string = SettingsLogic.diagnostics(
                    version: SettingsLogic.appVersion, build: SettingsLogic.appBuild,
                    system: UIDevice.current.systemVersion
                )
                copiedDiagnostics = true
            }
        } label: {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(SettingsLogic.versionText(version: SettingsLogic.appVersion, build: SettingsLogic.appBuild, commit: SettingsLogic.appCommit))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .sensoryFeedback(.success, trigger: copiedDiagnostics)
        .overlay(alignment: .bottomTrailing) {
            if copiedDiagnostics {
                Text("Diagnostics copied").font(.caption2).foregroundStyle(.secondary)
                    .task { try? await Task.sleep(for: .seconds(2)); copiedDiagnostics = false }
            }
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
            case .theme: ThemeSettings()
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
