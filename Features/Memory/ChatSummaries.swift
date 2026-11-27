import Foundation
import SwiftData

extension MemoryStore {
    /// The chat's one summary item, if it has one.
    func summary(of threadID: UUID) -> MemoryRecord? {
        items.first { $0.kind == .chatSummary && $0.sourceThreadID == threadID }
    }

    /// Saves the chat's summary, or replaces the one it had.
    func storeSummary(_ text: String, for thread: ThreadRecord, scope: MemoryScope, now: Date = Date()) throws {
        if let existing = summary(of: thread.id) {
            existing.text = text
            existing.scope = scope
            existing.updatedAt = now
            try context.save()
        } else {
            try add(text, kind: .chatSummary, origin: .extracted, scope: scope, sourceThreadID: thread.id, now: now)
        }
    }
}

/// Runs a summary request without tools and returns the cleaned summary, or nil.
enum ChatSummaryGenerator {
    @MainActor
    static func summary(for plan: ChatSummaryPlan, registry: EngineRegistry) async -> String? {
        var params = GenerationParams()
        params.temperature = 0.2
        params.maxTokens = ChatSummaryLogic.maxTokens
        params.systemPrompt = plan.system
        var text = ""
        do {
            for try await delta in registry.engine(for: plan.model).stream(model: plan.model, messages: plan.messages, params: params, tools: nil) {
                if case .text(let piece) = delta { text += piece }
            }
        } catch {
            return nil
        }
        return ChatSummaryLogic.clean(text)
    }
}
