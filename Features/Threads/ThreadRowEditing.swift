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
    /// The one long-press menu of a chat row (pin, rename, share, archive, delete) with a preview of the chat, plus
    /// swipe actions for the two quick ones. The sidebar, View all and the archived list all use it.
    func threadActions(_ thread: ThreadRecord, editing: Binding<ThreadEditing>) -> some View {
        modifier(ThreadRowMenu(thread: thread, editing: editing))
    }

    /// The rename alert and the delete confirmation that the row actions open. Attach once, to the list.
    func threadEditingDialogs(_ editing: Binding<ThreadEditing>) -> some View {
        modifier(ThreadEditingDialogs(editing: editing))
    }
}

private struct ThreadRowMenu: ViewModifier {
    let thread: ThreadRecord
    @Binding var editing: ThreadEditing
    @Environment(ShellModel.self) private var shell

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                pinButton.tint(.gray)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                archiveButton.tint(.indigo)
            }
            .contextMenu {
                pinButton
                Button { editing.beginRename(thread) } label: { Label("Rename", systemImage: "pencil") }
                    .accessibilityIdentifier("thread.menu.rename")
                ShareLink(item: ThreadShareItem(thread), preview: SharePreview(thread.title)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("thread.menu.share")
                archiveButton
                Button(role: .destructive) { editing.deleting = thread } label: { Label("Delete", systemImage: "trash") }
                    .accessibilityIdentifier("thread.menu.delete")
            } preview: {
                ThreadMenuPreview(thread: thread)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: thread.isPinned)
    }

    private var pinButton: some View {
        Button { ThreadActions.togglePin(thread) } label: {
            Label(thread.isPinned ? "Unpin" : "Pin", systemImage: thread.isPinned ? "pin.slash" : "pin")
        }
        .accessibilityIdentifier("thread.menu.pin")
    }

    private var archiveButton: some View {
        Button {
            ThreadActions.toggleArchive(thread)
            if thread.isArchived { shell.threadArchived(thread.id) }
        } label: {
            Label(thread.isArchived ? "Unarchive" : "Archive", systemImage: thread.isArchived ? "tray.and.arrow.up" : "archivebox")
        }
        .accessibilityIdentifier("thread.menu.archive")
    }
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
