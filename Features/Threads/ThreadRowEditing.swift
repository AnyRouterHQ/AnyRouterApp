import SwiftData
import SwiftUI

/// Rename and delete state for a list of threads. The sidebar and the search screen share it.
struct ThreadEditing {
    var renaming: ThreadRecord?
    var renameText = ""
    var deleting: ThreadRecord?

    mutating func beginRename(_ thread: ThreadRecord) {
        renameText = thread.title
        renaming = thread
    }
}

extension View {
    /// Swipe actions (pin, delete) and a context menu (rename, pin, delete) for a thread row.
    func threadActions(_ thread: ThreadRecord, editing: Binding<ThreadEditing>) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { editing.wrappedValue.deleting = thread } label: { Label("Delete", systemImage: "trash") }
            Button { ThreadActions.togglePin(thread) } label: { pinLabel(thread) }.tint(.gray)
        }
        .contextMenu {
            Button { editing.wrappedValue.beginRename(thread) } label: { Label("Rename", systemImage: "pencil") }
            Button { ThreadActions.togglePin(thread) } label: { pinLabel(thread) }
            Button(role: .destructive) { editing.wrappedValue.deleting = thread } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// The rename alert and the delete confirmation that the row actions open. Attach once, to the list.
    func threadEditingDialogs(_ editing: Binding<ThreadEditing>) -> some View {
        modifier(ThreadEditingDialogs(editing: editing))
    }
}

private func pinLabel(_ thread: ThreadRecord) -> some View {
    Label(thread.isPinned ? "Unpin" : "Pin", systemImage: thread.isPinned ? "pin.slash" : "pin")
}

private struct ThreadEditingDialogs: ViewModifier {
    @Binding var editing: ThreadEditing
    @Environment(ShellModel.self) private var shell
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .alert("Rename chat", isPresented: Binding(get: { editing.renaming != nil }, set: { if !$0 { editing.renaming = nil } })) {
                TextField("Title", text: $editing.renameText)
                Button("Cancel", role: .cancel) { editing.renaming = nil }
                Button("Save") {
                    if let thread = editing.renaming { ThreadActions.rename(thread, to: editing.renameText) }
                    editing.renaming = nil
                }
            }
            .confirmationDialog(
                "Delete this chat?",
                isPresented: Binding(get: { editing.deleting != nil }, set: { if !$0 { editing.deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let thread = editing.deleting { delete(thread) }
                    editing.deleting = nil
                }
                Button("Cancel", role: .cancel) { editing.deleting = nil }
            } message: {
                Text("This removes the chat and its messages from this device.")
            }
    }

    private func delete(_ thread: ThreadRecord) {
        let id = thread.id
        ThreadActions.delete(thread, in: context)
        shell.threadDeleted(id)
    }
}
