import Foundation
import SwiftData

/// The chat's notes on the main actor, where the thread lives.
@MainActor
final class ChatNotes {
    private let context: ModelContext
    private let thread: ThreadRecord

    init(context: ModelContext, thread: ThreadRecord) {
        self.context = context
        self.thread = thread
    }

    func replace(_ arguments: JSONValue) throws -> String {
        guard !ChatViewModel.isGone(thread) else { throw BuiltInToolError("The chat was deleted.") }
        let items = try NotesLogic.items(from: arguments)
        thread.notes = items
        try? context.save()
        return NotesLogic.reply(items)
    }

    var recitation: String? {
        ChatViewModel.isGone(thread) ? nil : NotesLogic.recitation(thread.notes)
    }
}

/// `notes`: the cloud model's working list for this chat. It changes only the model's own list, and its row shows the
/// whole new list, so it never asks.
struct NotesTool: BuiltInTool {
    let notes: ChatNotes
    let sideEffect = ToolSideEffect.write
    let undoesInsteadOfAsking = true
    let name = NotesLogic.name
    let title = "Notes"
    let summary = "The model's list for a long task"
    let description = NotesLogic.description
    let schema = JSONSchema(parsing: NotesLogic.schema)

    func run(_ arguments: JSONValue) async throws -> String { try await notes.replace(arguments) }
}
