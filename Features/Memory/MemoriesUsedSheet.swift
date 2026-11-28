import SwiftData
import SwiftUI

/// "Used 2 memories" under a reply opens this list: what was put in front of the question, each with Forget.
struct MemoriesUsedSheet: View {
    let hits: [MemoryHit]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var forgotten: Set<UUID> = []
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(hits, id: \.memoryID) { hit in
                        Text(hit.text)
                            .foregroundStyle(forgotten.contains(hit.memoryID) ? .secondary : .primary)
                            .strikethrough(forgotten.contains(hit.memoryID))
                            .swipeActions {
                                if !forgotten.contains(hit.memoryID) {
                                    Button("Forget", role: .destructive) { forget(hit) }
                                        .accessibilityIdentifier("memory.forget")
                                }
                            }
                    }
                } footer: {
                    Text(failure ?? "These were in front of your question for this reply. Swipe one to forget it.")
                }
            }
            .navigationTitle("Memories used")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func forget(_ hit: MemoryHit) {
        do {
            try MemoryStore(context: context).forget(hit.memoryID)
            forgotten.insert(hit.memoryID)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
