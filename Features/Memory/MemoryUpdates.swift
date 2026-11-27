import Foundation
import SwiftData

/// Writes from the chat: "Remember that …" in a message, "Remember" on selected reply text, and Undo and Edit on the
/// reply's "Memory updated" row.
extension MemoryStore {
    /// Saves what the user's message asks to remember, by the Memory settings. Nil when it asks nothing, memory is off
    /// (in Settings or for this chat), or it is an automatic save and those are off. An item from a chat with a model on
    /// this device stays off cloud models.
    func remember(
        _ text: String, messageID: UUID, thread: ThreadRecord, source: ModelSource, settings: AppSettings
    ) -> MemoryUpdate? {
        guard settings.useMemory, !thread.memoryOff, let candidate = RememberLogic.candidate(in: text),
              candidate.explicit || settings.saveMemoriesAutomatically else { return nil }
        return save(candidate.text, kind: candidate.kind, source: source, threadID: thread.id, messageID: messageID)
    }

    /// "Remember" on text selected in a reply: a pinned note, shown as a row on that reply.
    func pin(_ text: String, from reply: MessageRecord) throws {
        let source = reply.modelID.flatMap { ModelSource(rawValue: String($0.prefix { $0 != "/" })) } ?? .apple
        let update = save(text, kind: .note, source: source, threadID: reply.thread?.id, messageID: reply.id)
        reply.memoryUpdates.append(update)
        try context.save()
    }

    /// An item from a chat with a model on this device stays off cloud models (`deviceOnly`). A refusal is a row too.
    private func save(_ text: String, kind: MemoryKind, source: ModelSource, threadID: UUID?, messageID: UUID) -> MemoryUpdate {
        let scope: MemoryScope = source == .anyrouter ? .everywhere : .deviceOnly
        do {
            let record = try add(text, kind: kind, origin: .askedInChat, scope: scope, sourceThreadID: threadID, sourceMessageID: messageID)
            return MemoryUpdate(memoryID: record.id, text: record.text, outcome: .saved)
        } catch MemoryError.duplicate {
            return MemoryUpdate(text: text, outcome: .alreadySaved)
        } catch {
            return MemoryUpdate(text: text, outcome: .refused(error.localizedDescription))
        }
    }

    /// Deletes the saved item and marks the row undone.
    func undo(_ update: MemoryUpdate, on message: MessageRecord) throws {
        if let record = try record(update.memoryID) { context.delete(record) }
        message.memoryUpdates = message.memoryUpdates.map {
            $0.id == update.id ? MemoryUpdate(id: $0.id, text: $0.text, outcome: .undone) : $0
        }
        try context.save()
    }

    /// Changes the saved item's text; the row shows the new text.
    func edit(_ update: MemoryUpdate, to text: String, on message: MessageRecord) throws {
        guard let record = try record(update.memoryID) else { return }
        try edit(record, text: text)
        message.memoryUpdates = message.memoryUpdates.map {
            $0.id == update.id ? MemoryUpdate(id: $0.id, memoryID: record.id, text: record.text, outcome: $0.outcome) : $0
        }
        try context.save()
    }

    /// "Forget" on a memory a reply used. One already deleted is gone either way.
    func forget(_ id: UUID) throws {
        guard let record = try record(id) else { return }
        try delete(record)
    }

    private func record(_ id: UUID?) throws -> MemoryRecord? {
        guard let id else { return nil }
        return try context.fetch(FetchDescriptor<MemoryRecord>(predicate: #Predicate { $0.id == id })).first
    }
}
