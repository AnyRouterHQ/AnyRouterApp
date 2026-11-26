import SwiftData
import SwiftUI

/// Privacy summary, the diagnostics opt-out, deleting the conversation history, and a link to the full text.
struct PrivacySettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ShellModel.self) private var shell
    @Environment(\.modelContext) private var context
    @Query private var threads: [ThreadRecord]

    @State private var confirmsDelete = false

    var body: some View {
        @Bindable var settings = settings
        List {
            Section { Text(LegalPage.Kind.privacy.summary) }
            Section {
                Button(role: .destructive) { confirmsDelete = true } label: {
                    Label("Delete All Conversations", systemImage: "trash")
                }
                .disabled(threads.isEmpty)
                .accessibilityIdentifier("privacy.deleteAll")
            } header: {
                Text("Conversations")
            } footer: {
                Text(SettingsLogic.conversationCountText(threads.count))
            }
            Section {
                Toggle("Share anonymous diagnostics", isOn: $settings.shareDiagnostics)
                    .disabled(!Diagnostics.isConfigured)
                    .accessibilityIdentifier("privacy.shareDiagnostics")
            } footer: {
                Text(Diagnostics.isConfigured
                    ? "Crash and hang reports and basic usage counts. Never chats, keys or emails. Off until you choose. Turning it on takes effect after the app restarts."
                    : "This build has no remote reporting set up, so nothing is shared. Crash reports stay on this device under Diagnostics.")
            }
            Section {
                ExternalLinkRow(title: "Read the full text on anyrouter.dev", systemImage: "hand.raised", destination: LegalPage.Kind.privacy.url)
            }
        }
        .confirmationDialog("Delete all conversations?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete All Conversations", role: .destructive) {
                ThreadActions.deleteAll(in: context)
                shell.selectedThreadID = nil
            }
        } message: {
            Text(SettingsLogic.deleteConversationsMessage(threads.count))
        }
    }
}
