import SwiftUI
import UIKit

/// Version (seven taps copy diagnostics for a bug report), Diagnostics, Terms and Licenses.
struct AboutSettings: View {
    @State private var versionTaps = 0
    @State private var copiedDiagnostics = false

    var body: some View {
        List {
            Section { versionRow }
            Section {
                ForEach(SettingsDestination.aboutPages, id: \.self) { destination in
                    NavigationLink(value: destination) {
                        ListRow(destination.title) { SettingsIcon(glyph: destination.glyph, color: destination.tileColor) }
                    }
                }
            }
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
            ListRow("Version") {
                SettingsIcon(glyph: .symbol("info"), color: .gray)
            } accessory: {
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
