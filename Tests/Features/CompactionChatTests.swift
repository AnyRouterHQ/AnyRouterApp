import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// One request an engine received: is it the summary request, what it carried, and the system prompt.
private struct CompactionEngineCall: Sendable {
    let isSummary: Bool
    let messages: [ChatMessage]
    let system: String?
}

private final class CompactionCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [CompactionEngineCall] = []
    var calls: [CompactionEngineCall] { lock.withLock { raw } }
    func add(_ call: CompactionEngineCall) { lock.withLock { raw.append(call) } }
}

/// Answers the summary request with `summary` (or fails when it is nil) and every other request with "Reply."
private struct CompactingEngine: ChatEngine {
    var source: ModelSource = .apple
    var model: ModelDescriptor
    var summary: String? = "They talked about actors."
    let log = CompactionCallLog()

    func availableModels() async throws -> [ModelDescriptor] { [model] }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        let isSummary = params.systemPrompt == CompactionLogic.summarizerPrompt
        log.add(CompactionEngineCall(isSummary: isSummary, messages: messages, system: params.systemPrompt))
        let answer = isSummary ? summary : "Reply."
        return AsyncThrowingStream { continuation in
            if let answer {
                continuation.yield(.text(answer))
                continuation.yield(.done(finishReason: "stop"))
                continuation.finish()
            } else {
                continuation.finish(throwing: TestFailure(message: "no summary"))
            }
        }
    }
}

@MainActor
struct CompactionChatTests {
    private struct Rig {
        let vm: ChatViewModel
        let engine: CompactingEngine
    }

    private func rig(window: Int, summary: String? = "They talked about actors.") async throws -> Rig {
        let model = ModelDescriptor(
            id: "apple/foundation", source: .apple, displayName: "Apple", contextLength: window, capabilities: ["chat"],
            sizeBytes: nil, isInstalled: true)
        let engine = CompactingEngine(model: model, summary: summary)
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let vm = ChatViewModel(
            thread: nil, context: ModelContext(try ModelContainer.anyRouter(inMemory: true)), registry: registry,
            settings: AppSettings(defaults: testDefaults()), models: models)
        return Rig(vm: vm, engine: engine)
    }

    private func say(_ vm: ChatViewModel, _ text: String) async {
        vm.input = text
        await vm.send()?.value
    }

    /// 64 tokens (TokenCountLogic), so five of them fill most of a 400-token window.
    private let long = String(repeating: "word ", count: 38)

    // MARK: By hand

    @Test func compactingByHandFoldsTheOlderMessagesAndKeepsThemOnScreen() async throws {
        let r = try await rig(window: 8_192)
        for index in 1...4 { await say(r.vm, "Question \(index)") }
        #expect(r.vm.messages.count == 8)
        #expect(r.vm.canCompact)
        await r.vm.compactConversation()?.value
        let compaction = try #require(r.vm.compactions.first)
        #expect(compaction.summary == "They talked about actors.")
        #expect(compaction.droppedCount == 6)
        #expect(compaction.lastMessageID == r.vm.messages[5].id)
        #expect(r.vm.messages.count == 8, "nothing is deleted")
        #expect(r.vm.phase == .idle)
        #expect(!r.vm.isCompacting)
        #expect(r.vm.statusNote == nil)
    }

    @Test func afterACompactionTheNextRequestCarriesTheSummaryAndOnlyTheRecentMessages() async throws {
        let r = try await rig(window: 8_192)
        for index in 1...4 { await say(r.vm, "Question \(index)") }
        await r.vm.compactConversation()?.value
        await say(r.vm, "Question 5")
        let request = try #require(r.engine.log.calls.last)
        #expect(!request.isSummary)
        #expect(request.messages.count == 3)
        #expect(request.messages.map(\.content).dropFirst() == ["Reply.", "Question 5"])
        let first = try #require(request.messages.first?.content)
        #expect(first.hasPrefix(PromptAssembler.summaryHeading) && first.contains("They talked about actors.") && first.hasSuffix("Question 4"),
                "the summary goes with the first kept question")
        #expect(request.system?.contains("They talked about actors.") != true, "a compaction leaves the system message as it was")
    }

    @Test func aChatTooShortToFoldHasNothingToCompact() async throws {
        let r = try await rig(window: 8_192)
        #expect(r.vm.compactions.isEmpty, "a chat that has no thread yet has no compactions")
        #expect(r.vm.compactConversation() == nil)
        #expect(!r.vm.canCompact)
        await say(r.vm, "Hi")
        #expect(r.vm.compactConversation() == nil)
    }

    @Test func aSummaryThatFailsLeavesTheChatAsItWasAndSaysSo() async throws {
        let r = try await rig(window: 8_192, summary: nil)
        for index in 1...4 { await say(r.vm, "Question \(index)") }
        await r.vm.compactConversation()?.value
        #expect(r.vm.compactions.isEmpty)
        #expect(r.vm.errorMessage == "Could not shorten the conversation.")
        #expect(r.vm.phase == .idle)
    }

    // MARK: By itself

    @Test func aChatFarFromFullIsNeverCompacted() async throws {
        let r = try await rig(window: 400)
        for _ in 1...4 { await say(r.vm, long) }
        #expect(r.engine.log.calls.allSatisfy { !$0.isSummary })
        #expect(r.vm.compactions.isEmpty)
    }

    @Test func aChatThatFillsTheWindowIsShortenedBeforeTheReplyAndTheReplyStillComes() async throws {
        let r = try await rig(window: 400)
        for _ in 1...4 { await say(r.vm, long) }
        await say(r.vm, long)
        let calls = r.engine.log.calls
        #expect(calls.filter(\.isSummary).count == 1)
        let chatCall = try #require(calls.last)
        #expect(!chatCall.isSummary, "the summary comes first, then the reply")
        #expect(chatCall.messages.first?.content.contains("They talked about actors.") == true)
        #expect(chatCall.system?.contains("They talked about actors.") != true)
        #expect(chatCall.messages.count == 5, "the last two exchanges and the new question")
        let compaction = try #require(r.vm.compactions.first)
        #expect(compaction.droppedCount == 4)
        #expect(r.vm.messages.last?.content == "Reply.")
        #expect(r.vm.messages.count == 10)
        #expect(r.vm.compactionNote == nil)
    }

    @Test func ifTheSummaryFailsTheChatIsSentAsItIsWithANote() async throws {
        let r = try await rig(window: 400, summary: nil)
        for _ in 1...5 { await say(r.vm, long) }
        let chatCall = try #require(r.engine.log.calls.last)
        #expect(!chatCall.isSummary)
        #expect(chatCall.messages.count == 9, "nothing was folded")
        #expect(r.vm.compactions.isEmpty)
        #expect(r.vm.compactionNote == "Could not shorten the conversation. It was sent as it is.")
        #expect(r.vm.messages.last?.content == "Reply.")
    }
}
