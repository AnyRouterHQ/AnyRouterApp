import SwiftData
import SwiftUI

/// "Memory updated" in a reply (agent design 2.3): one trace row; open, it shows the saved text with Undo and Edit.
struct MemoryUpdateRow: View {
    let update: MemoryUpdate
    let message: MessageRecord
    @Environment(\.modelContext) private var context
    @State private var isExpanded = false
    @State private var isEditing = false
    @State private var draft = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                TraceRow(symbol: "brain", status: status, isExpanded: isExpanded) {
                    Text(RememberLogic.title(of: update.outcome))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("memory.update")
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(update.text).font(.footnote)
                    if case .refused(let reason) = update.outcome {
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let failure {
                        Text(failure).font(.footnote).foregroundStyle(.secondary)
                    }
                    if update.outcome == .saved {
                        HStack(spacing: 16) {
                            Button { perform { try MemoryStore(context: context).undo(update, on: message) } } label: {
                                Text("Undo").frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityIdentifier("memory.undo")
                            Button {
                                draft = update.text
                                isEditing = true
                            } label: {
                                Text("Edit").frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityIdentifier("memory.edit")
                        }
                        .font(.footnote)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.leading, TraceRowMetrics.contentInset)
            }
        }
        .alert("Edit memory", isPresented: $isEditing) {
            TextField("Memory", text: $draft)
                .accessibilityIdentifier("memory.edit.field")
            Button("Cancel", role: .cancel) {}
            Button("Save") { perform { try MemoryStore(context: context).edit(update, to: draft, on: message) } }
        }
    }

    private var status: TraceStatus? {
        switch update.outcome {
        case .saved: .done
        case .refused: .failed
        case .alreadySaved, .undone: nil
        }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
