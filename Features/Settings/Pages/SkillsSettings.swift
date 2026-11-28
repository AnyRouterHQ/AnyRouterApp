import SwiftData
import SwiftUI

/// The skills a cloud model can read: the ones that come with the app, and the ones you own. Each of yours has a switch
/// and a swipe to delete; add one from a link or sync the skills in your AnyRouter hubs. Skills are text a model reads.
struct SkillsSettings: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \SkillRecord.name) private var records: [SkillRecord]

    @State private var model = SkillsModel()
    @State private var asksForLink = false
    @State private var link = ""

    private var store: SkillStore { SkillStore(context: context) }
    private var signedIn: Bool { app.account.state.isSignedIn }

    var body: some View {
        Form {
            if let failure = model.failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings.skills.error")
                }
            }
            Section {
                Text("A skill is a set of steps a cloud model reads when your request matches it. A skill never turns on a tool and never changes what you approve.")
                    .foregroundStyle(.secondary)
            }
            Section("Built in") {
                ForEach(SkillLogic.bundled) { skill in
                    label(name: skill.name, summary: skill.description, source: skill.source)
                        .accessibilityIdentifier("settings.skills.bundled")
                }
            }
            Section {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No skills of your own",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Import a SKILL.md from a link, or sync the skills in your AnyRouter hubs."))
                        .accessibilityIdentifier("settings.skills.empty")
                }
                ForEach(records) { record in
                    Toggle(isOn: Binding(
                        get: { record.enabled },
                        set: { on in model.perform { try store.setEnabled(record, on) } })
                    ) {
                        label(name: record.name, summary: record.summary, source: record.source.skillSource)
                    }
                    .swipeActions {
                        Button(role: .destructive) { model.perform { try store.delete(record) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityIdentifier("settings.skills.row")
                }
            } header: {
                Text("Yours")
            }
            Section {
                Button { asksForLink = true } label: { Label("Import from URL", systemImage: "link") }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("settings.skills.import")
                Button {
                    Task { await model.sync(tokens: app.tokenStore, into: store) }
                } label: {
                    HStack {
                        Label("Sync from AnyRouter", systemImage: "arrow.triangle.2.circlepath")
                        if model.isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!signedIn || model.isWorking)
                .accessibilityIdentifier("settings.skills.sync")
            } footer: {
                Text(model.syncNote ?? (signedIn ? "Syncing adds the skills in your AnyRouter hubs and removes the ones you took out." : "Sign in with AnyRouter to sync the skills in your hubs."))
            }
        }
        .formSwitches()
        .alert("Import from URL", isPresented: $asksForLink) {
            TextField("https://example.com/SKILL.md", text: $link)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings.skills.link")
            Button("Import") {
                let text = link
                link = ""
                Task { await model.importFromURL(text) }
            }
            Button("Cancel", role: .cancel) { link = "" }
        } message: {
            Text("A link to a SKILL.md file, https only, up to 64 KB.")
        }
        .alert(
            "Save this skill?",
            isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.discardImport() } }),
            presenting: model.pending
        ) { _ in
            Button("Save") { model.confirmImport(into: store) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(SkillImportLogic.preview(pending.draft))
        }
    }

    private func label(name: String, summary: String, source: Skill.Source) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(source.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
