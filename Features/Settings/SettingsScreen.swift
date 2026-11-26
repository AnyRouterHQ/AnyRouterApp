import SwiftData
import SwiftUI
import UIKit

/// Settings as a native drill-down: a sheet with a navigation stack and a grouped inset list.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
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
    }
}

private struct SettingsList: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ShellModel.self) private var shell
    @Environment(\.modelContext) private var context

    @State private var confirmsDelete = false
    @State private var versionTaps = 0
    @State private var copiedDiagnostics = false

    var body: some View {
        @Bindable var settings = settings
        List {
            Section { AccountCard() }
            ForEach(SettingsDestination.Group.allCases, id: \.self) { group in
                Section(group.title) {
                    ForEach(group.destinations, id: \.self) { destination in
                        NavigationLink(value: destination) { Label(destination.title, systemImage: destination.systemImage) }
                    }
                    if group == .chat {
                        Toggle(isOn: $settings.showKeyboardOnLaunch) {
                            Label("Show keyboard on launch", systemImage: "keyboard")
                        }
                        .accessibilityIdentifier("settings-show-keyboard")
                        Button(role: .destructive) { confirmsDelete = true } label: {
                            Label("Delete conversation history", systemImage: "trash")
                        }
                    }
                    if group == .about { versionRow }
                }
            }
        }
        .confirmationDialog("Delete all conversations?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                ThreadActions.deleteAll(in: context)
                shell.selectedThreadID = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every chat and its messages from this device.")
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
            case .manageModels: HubScreen()
            case .defaultModel: DefaultModelSettings()
            case .inference: InferenceSettings()
            case .catalogSources: CatalogSourcesSheet()
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
