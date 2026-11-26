import Foundation
import SwiftData

/// Thread mutations behind the sidebar's swipe actions, context menu and Settings.
@MainActor
enum ThreadActions {
    static func togglePin(_ thread: ThreadRecord) { thread.isPinned.toggle() }

    /// An empty name keeps the old title.
    static func rename(_ thread: ThreadRecord, to proposed: String) {
        thread.title = ThreadListLogic.renamed(proposed, current: thread.title)
    }

    static func delete(_ thread: ThreadRecord, in context: ModelContext) {
        context.delete(thread)
    }

    /// Removes every thread; messages go with them (cascade).
    static func deleteAll(in context: ModelContext) {
        try? context.delete(model: ThreadRecord.self)
    }
}
