import Foundation
import SwiftData
import Testing
@testable import AnyRouter

private final class MessageLimit: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    private var summaries = 0
    init(_ value: Int) { self.value = value }
    var limit: Int {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
    var summaryCount: Int { lock.withLock { summaries } }
    func summarized() { lock.withLock { summaries += 1 } }
}

/// Apple's model: answers the summary request, and fails a chat request that carries more messages than `limit` with
/// the words its framework uses for a full window.
private struct WindowEngine: ChatEngine {
    let source: ModelSource = .apple
    let model = ModelDescriptor(
        id: "apple/foundation", source: .apple, displayName: "Apple", contextLength: 4096, capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
    let limit: MessageLimit

    func availableModels() async throws -> [ModelDescriptor] { [model] }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams) -> AsyncThrowingStream<ChatDelta, Error> {
        let isSummary = params.systemPrompt == CompactionLogic.summarizerPrompt
        if isSummary { limit.summarized() }
        let fails = !isSummary && messages.count > limit.limit
        return AsyncThrowingStream { continuation in
            if fails {
                continuation.finish(throwing: TestFailure(message: "Exceeded the context window size."))
                return
            }
            continuation.yield(.text(isSummary ? "They talked about actors." : "Reply."))
            continuation.yield(.done(finishReason: "stop"))
            continuation.finish()
        }
    }
}

/// Agent design 3.5: on Apple's context error the chat folds once and asks again; a second failure stays.
@MainActor
struct ContextRetryTests {
    private func rig(limit: Int) async throws -> (vm: ChatViewModel, limit: MessageLimit) {
        let box = MessageLimit(limit)
        let registry = EngineRegistry()
        registry.register(WindowEngine(limit: box))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let vm = ChatViewModel(
            thread: nil, context: ModelContext(try ModelContainer.anyRouter(inMemory: true)), registry: registry,
            settings: AppSettings(defaults: testDefaults()), models: models)
        return (vm, box)
    }

    private func say(_ vm: ChatViewModel, _ text: String) async {
        vm.input = text
        await vm.send()?.value
        // The fold and the second request run in tasks of their own.
        _ = await waitUntil { vm.phase == .idle && vm.messages.last?.role == .assistant }
    }

    @Test func aFullWindowIsShortenedOnceAndTheQuestionIsAskedAgain() async throws {
        let r = try await rig(limit: 4)
        await say(r.vm, "Question 1")
        await say(r.vm, "Question 2")
        await say(r.vm, "Question 3")
        #expect(await waitUntil { r.vm.messages.last?.content == "Reply." && r.vm.phase == .idle && r.vm.compactions.count == 1 })
        #expect(r.vm.messages.last?.failure == nil)
        #expect(r.vm.messages.filter { $0.role == .assistant }.count == 3, "the failed reply was replaced")
        #expect(r.limit.summaryCount == 1)
    }

    @Test func aSecondFailureStaysWithShortenChat() async throws {
        let r = try await rig(limit: 10)
        await say(r.vm, "Question 1")
        await say(r.vm, "Question 2")
        r.limit.limit = 0
        await say(r.vm, "Question 3")
        #expect(await waitUntil { r.vm.messages.last?.failure?.kind == .contextTooLong && r.vm.phase == .idle && r.vm.compactions.count == 1 })
        #expect(r.limit.summaryCount == 1, "folded once, not again")
    }
}
