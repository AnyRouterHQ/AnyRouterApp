import SwiftUI

/// Privacy summary, the diagnostics opt-out, and a link to the full text.
struct PrivacySettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        List {
            Section { Text(LegalPage.Kind.privacy.summary) }
            Section {
                Toggle("Share anonymous diagnostics", isOn: $settings.shareDiagnostics)
                    .disabled(!Diagnostics.isConfigured)
                    .accessibilityIdentifier("privacy.shareDiagnostics")
            } footer: {
                Text(Diagnostics.isConfigured
                    ? "Crash and hang reports and basic usage counts. Never chats, keys or emails. Off until you choose. Turning it on takes effect after the app restarts."
                    : "This build has no remote reporting set up, so nothing is shared. Crash reports stay on this device under Diagnostics.")
            }
            Section { Link("Read the full text on anyrouter.dev", destination: LegalPage.Kind.privacy.url) }
        }
    }
}
