import SwiftData
import SwiftUI

/// What the app remembers about you: three switches, the saved items by kind, and Add and Delete all.
struct MemorySettings: View {
    private enum Editor: Identifiable {
        case add(MemoryKind)
        case edit(MemoryRecord)

        var id: String {
            switch self {
            case .add(let kind): "add-\(kind.rawValue)"
            case .edit(let record): record.id.uuidString
            }
        }

        var title: String {
            switch self {
            case .add(let kind): "Add \(kind.addTitle)"
            case .edit: "Edit memory"
            }
        }
    }

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Query(sort: \MemoryRecord.updatedAt, order: .reverse) private var records: [MemoryRecord]
    @Query private var threads: [ThreadRecord]

    @State private var editor: Editor?
    @State private var draft = ""
    @State private var confirmsDeleteAll = false
    @State private var failure: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings.memory.error")
                }
            }
            Section {
                Toggle(isOn: $settings.useMemory) { Label("Use memory", systemImage: "brain") }
                    .accessibilityIdentifier("settings.memory.use")
                Toggle(isOn: $settings.saveMemoriesAutomatically) { Label("Save memories automatically", systemImage: "square.and.arrow.down") }
                    .disabled(!settings.useMemory)
                    .accessibilityIdentifier("settings.memory.auto")
            } footer: {
                Text("Memory lets chats start with what you told the app before. Items you type here go to the model you chat with, including cloud models. Turn off automatic saving to keep only what you add yourself or ask to remember.")
            }
            Section {
                Toggle(isOn: $settings.deviceMemoriesInCloudChats) { Label("Use on-device memories in cloud chats", systemImage: "iphone.and.arrow.right.outward") }
                    .disabled(!settings.useMemory)
                    .accessibilityIdentifier("settings.memory.cloud")
            } footer: {
                Text("Memories saved from chats with models on this device stay off cloud models unless you turn this on.")
            }
            if records.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No memories yet",
                        systemImage: "brain",
                        description: Text("Add something you want chats to know, like your name or how you like answers."))
                        .accessibilityIdentifier("settings.memory.empty")
                }
            }
            ForEach(MemoryStore.groups(records)) { group in
                Section(group.kind.groupTitle) {
                    ForEach(group.records) { record in row(record) }
                }
            }
            Section {
                Button(role: .destructive) { confirmsDeleteAll = true } label: {
                    Label("Delete all memories", systemImage: "trash")
                }
                .disabled(records.isEmpty)
                .accessibilityIdentifier("settings.memory.deleteAll")
            }
        }
        .formSwitches()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(MemoryKind.addable, id: \.self) { kind in
                        Button(kind.addTitle) { open(.add(kind), text: "") }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .accessibilityIdentifier("settings.memory.add")
            }
        }
        .alert(
            editor?.title ?? "", isPresented: Binding(get: { editor != nil }, set: { if !$0 { editor = nil } }),
            presenting: editor
        ) { editor in
            TextField("Memory", text: $draft)
                .textInputAutocapitalization(.sentences)
                .accessibilityIdentifier("settings.memory.field")
            Button("Save") { save(editor) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Keep it short. It goes to the model you chat with.")
        }
        .confirmationDialog("Delete all memories?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
            Button("Delete All Memories", role: .destructive) { perform { try MemoryStore(context: context).deleteAll() } }
        } message: {
            Text("This removes every memory on this device. Your chats stay.")
        }
    }

    private func row(_ record: MemoryRecord) -> some View {
        Button { open(.edit(record), text: record.text) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.text)
                Text(MemoryStore.sourceText(of: record, threadTitle: threadTitle(of: record)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.primary)
        .swipeActions {
            Button(role: .destructive) { perform { try MemoryStore(context: context).delete(record) } } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("settings.memory.row")
    }

    private func threadTitle(of record: MemoryRecord) -> String? {
        threads.first { $0.id == record.sourceThreadID }?.title
    }

    private func open(_ next: Editor, text: String) {
        failure = nil
        draft = text
        editor = next
    }

    private func save(_ editor: Editor) {
        perform {
            let store = MemoryStore(context: context)
            switch editor {
            case .add(let kind): try store.add(draft, kind: kind)
            case .edit(let record): try store.edit(record, text: draft)
            }
        }
    }

    /// A refused write shows its reason at the top of the page, where it cannot be missed.
    private func perform(_ work: () throws -> Void) {
        failure = nil
        do { try work() } catch { failure = error.localizedDescription }
    }
}
