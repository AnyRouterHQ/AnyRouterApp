import Foundation
import SwiftData

/// Thread mutations behind the sidebar's swipe actions, context menu and Settings.
@MainActor
enum ThreadActions {
    static func togglePin(_ thread: ThreadRecord) { thread.isPinned.toggle() }

    /// Archiving hides a chat from the sidebar and the search list without deleting it; pin and messages stay.
    static func toggleArchive(_ thread: ThreadRecord) { thread.isArchived.toggle() }

    /// An empty name keeps the old title. A new title is the user's: a generated one never replaces it.
    static func rename(_ thread: ThreadRecord, to proposed: String) {
        let title = ThreadListLogic.renamed(proposed, current: "")
        guard !title.isEmpty else { return }
        thread.title = title
        thread.titleSource = .user
    }

    /// The thread's attachment files go with it.
    static func delete(_ thread: ThreadRecord, in context: ModelContext, files: AttachmentStore = .shared) {
        files.deleteThread(thread.id)
        context.delete(thread)
    }

    /// Removes every thread; messages go with them (cascade).
    static func deleteAll(in context: ModelContext, files: AttachmentStore = .shared) {
        files.deleteAll()
        try? context.delete(model: ThreadRecord.self)
    }
}
