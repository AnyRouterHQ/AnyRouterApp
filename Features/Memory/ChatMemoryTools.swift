import Foundation
import SwiftData

/// The cloud model's `memory` and `search_chats` tools for one reply (agent design 2.4). Built only for an AnyRouter
/// model while memory is on for the chat. Every write shows on the reply as a row with Undo. The model sees items from
/// on-device chats, and searches on-device chats, only when the user allowed it.
@MainActor
final class ChatMemoryTools {
    private let context: ModelContext
    private let thread: ThreadRecord
    private let reply: MessageRecord
    private let settings: AppSettings

    init(context: ModelContext, thread: ThreadRecord, reply: MessageRecord, settings: AppSettings) {
        self.context = context
        self.thread = thread
        self.reply = reply
        self.settings = settings
    }

    var tools: [any BuiltInTool] { [MemoryTool(backend: self), SearchChatsTool(backend: self)] }

    func memory(_ arguments: JSONValue) throws -> String {
        let store = MemoryStore(context: context)
        let visible = try store.all().filter {
            $0.kind != .chatSummary
                && MemoryProfileLogic.allows($0.scope, source: .anyrouter, deviceMemoriesInCloud: settings.deviceMemoriesInCloudChats)
        }
        switch try MemoryToolLogic.request(from: arguments) {
        case .search(let query):
            let found: [MemoryRecord]
            if query.isEmpty {
                found = visible.sorted { $0.createdAt > $1.createdAt }
            } else {
                let ranked = MemoryRecallLogic.rank(query, visible.map { MemoryRecallLogic.Candidate(id: $0.id, text: $0.text) })
                found = ranked.compactMap { hit in visible.first { $0.id == hit.candidate.id } }
            }
            return MemoryToolLogic.render(found.prefix(MemoryToolLogic.maxSearchItems).map {
                MemoryToolLogic.Item(id: $0.id, kind: $0.kind, text: $0.text)
            })
        case .add(let text, let kind):
            guard settings.saveMemoriesAutomatically else {
                throw BuiltInToolError("The user turned off automatic saving. They can say \"remember that …\" themselves.")
            }
            let update = store.save(text, kind: kind, origin: .modelTool, source: .anyrouter, threadID: thread.id, messageID: reply.id)
            return record(update)
        case .remove(let id):
            guard let item = visible.first(where: { $0.id == id }) else { throw BuiltInToolError("No saved memory has that id.") }
            let update = MemoryUpdate(text: item.text, outcome: .removed, kind: item.kind, scope: item.scope)
            try store.delete(item)
            return record(update)
        }
    }

    func searchChats(_ arguments: JSONValue) throws -> String {
        guard let query = arguments["query"]?.string, !query.isEmpty else { throw BuiltInToolError("Missing the \"query\" argument.") }
        var candidates: [UUID: MessageRecord] = [:]
        for word in Set(MemoryRecallLogic.words(query)).prefix(8) {
            var descriptor = FetchDescriptor<MessageRecord>(
                predicate: #Predicate { $0.content.localizedStandardContains(word) }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            descriptor.fetchLimit = 200
            for message in try context.fetch(descriptor) { candidates[message.id] = message }
        }
        let currentID = thread.id
        let crossAllowed = settings.deviceMemoriesInCloudChats
        let allowed = candidates.values.filter { message in
            guard let other = message.thread, other.id != currentID else { return false }
            return crossAllowed || MemoryToolLogic.isCloudChat(replyModelIDs: other.messages.filter { $0.role == .assistant }.map(\.modelID))
        }
        let ranked = MemoryRecallLogic.rank(query, allowed.map { MemoryRecallLogic.Candidate(id: $0.id, text: $0.content) })
        var seenThreads = Set<UUID>()
        var chats: [MemoryToolLogic.FoundChat] = []
        let summaries = try MemoryStore(context: context).all().filter { $0.kind == .chatSummary }
        for hit in ranked where chats.count < MemoryToolLogic.maxChats {
            guard let message = candidates[hit.candidate.id], let other = message.thread, seenThreads.insert(other.id).inserted else { continue }
            chats.append(MemoryToolLogic.FoundChat(
                title: other.title, date: message.createdAt,
                summary: summaries.first { $0.sourceThreadID == other.id }?.text,
                excerpt: MemoryToolLogic.excerpt(message.content, query: query)))
        }
        return MemoryToolLogic.render(chats: chats)
    }

    /// The row on the reply, then the words the model reads.
    private func record(_ update: MemoryUpdate) -> String {
        reply.memoryUpdates.append(update)
        try? context.save()
        return MemoryToolLogic.reply(to: update.outcome)
    }
}

/// `memory`: search, add or remove one saved item. A write that never asks: the reply shows each change with Undo.
struct MemoryTool: BuiltInTool {
    let backend: ChatMemoryTools
    let sideEffect = ToolSideEffect.write
    let undoesInsteadOfAsking = true
    let name = MemoryToolLogic.memoryName
    let title = "Memory"
    let summary = "What you told the app before"
    let description = MemoryToolLogic.memoryDescription
    let inputSchemaJSON = MemoryToolLogic.memorySchema

    func run(_ arguments: JSONValue) async throws -> String { try await backend.memory(arguments) }
}

/// `search_chats`: earlier chats that mention the query. It reads the user's own chats, so it is a sensitive read.
struct SearchChatsTool: BuiltInTool {
    let backend: ChatMemoryTools
    let sideEffect = ToolSideEffect.sensitiveRead
    let name = MemoryToolLogic.searchChatsName
    let title = "Search chats"
    let summary = "Find earlier chats"
    let description = MemoryToolLogic.searchChatsDescription
    let inputSchemaJSON = MemoryToolLogic.searchChatsSchema

    func run(_ arguments: JSONValue) async throws -> String { try await backend.searchChats(arguments) }
}
