import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// Answers a chat reply with "Reply." and the title request with `title` (or fails). A title request waits for `gate`.
private struct TitleEngine: ChatEngine {
    var source: ModelSource = .apple
    var models: [ModelDescriptor]
    var title: String? = "Trip to Lisbon"
    var gate: Flag?
    let titleCalls = Counter()
    let replyCalls = Counter()

    func availableModels() async throws -> [ModelDescriptor] { models }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        let isTitle = params.systemPrompt == TitleLogic.systemPrompt
        _ = isTitle ? titleCalls.next() : replyCalls.next()
        let answer = isTitle ? title : "Reply."
        let gate = isTitle ? self.gate : nil
        let maxTokens = params.maxTokens
        return AsyncThrowingStream { continuation in
            let producer = Task {
                while let gate, !gate.value { try? await Task.sleep(for: .milliseconds(5)) }
                if let answer, !isTitle || maxTokens == TitleLogic.maxTokens {
                    continuation.yield(.text(answer))
                    continuation.yield(.done(finishReason: "stop"))
                    continuation.finish()
                } else {
                    continuation.finish(throwing: TestFailure(message: "no title"))
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}

@MainActor
struct GeneratedTitleChatTests {
    private struct Rig {
        let vm: ChatViewModel
        let apple: TitleEngine
        let cloud: TitleEngine?
    }

    private let appleModel = testModel()
    private let cloudModel = testModel(id: "anyrouter/openai/gpt-5", source: .anyrouter)

    private func rig(title: String? = "Trip to Lisbon", gate: Flag? = nil, withCloud: Bool = false, thread: ThreadRecord? = nil) async throws -> Rig {
        let apple = TitleEngine(source: .apple, models: [appleModel], title: title, gate: gate)
        let cloud = withCloud ? TitleEngine(source: .anyrouter, models: [cloudModel], title: title, gate: gate) : nil
        let registry = EngineRegistry()
        registry.register(apple)
        if let cloud { registry.register(cloud) }
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        if let thread { context.insert(thread) }
        let vm = ChatViewModel(
            thread: thread, context: context, registry: registry,
            settings: AppSettings(defaults: testDefaults()), models: models)
        vm.generatesTitles = true
        if withCloud { vm.choose(cloudModel) }
        return Rig(vm: vm, apple: apple, cloud: cloud)
    }

    private func say(_ vm: ChatViewModel, _ text: String) async {
        vm.input = text
        await vm.send()?.value
        await vm.titleTask?.value
    }

    @Test func theFirstReplyGivesTheChatAGeneratedTitle() async throws {
        let r = try await rig()
        await say(r.vm, "Plan a week in Lisbon")
        let thread = try #require(r.vm.thread)
        #expect(thread.title == "Trip to Lisbon")
        #expect(thread.titleSource == .generated)
        let asked = r.apple.titleCalls.next()
        #expect(asked == 2, "asked once, off the reply")
    }

    @Test func aGeneratedTitleIsAskedForOnlyOnce() async throws {
        let r = try await rig()
        await say(r.vm, "Plan a week in Lisbon")
        await say(r.vm, "And the second week?")
        let asked = r.apple.titleCalls.next()
        #expect(asked == 2)
        #expect(r.vm.thread?.title == "Trip to Lisbon")
    }

    @Test func aFailedTitleKeepsTheFirstMessageAndTriesAgainAfterTheNextReply() async throws {
        let failing = try await rig(title: nil)
        await say(failing.vm, "Plan a week in Lisbon")
        let thread = try #require(failing.vm.thread)
        #expect(thread.title == "Plan a week in Lisbon")
        #expect(thread.titleSource == .firstMessage)
        await say(failing.vm, "More")
        let asked = failing.apple.titleCalls.next()
        #expect(asked == 3, "the second reply asks again while the fallback stays")
        #expect(failing.vm.errorMessage == nil, "a failed title is quiet")
    }

    @Test func aTitleThatIsOnlyThinkingKeepsTheFallback() async throws {
        let r = try await rig(title: "<think>hmm")
        await say(r.vm, "Plan a week in Lisbon")
        #expect(r.vm.thread?.title == "Plan a week in Lisbon")
    }

    @Test func aTitleTheUserSetWhileTheModelWroteIsKept() async throws {
        let gate = Flag()
        let r = try await rig(gate: gate)
        r.vm.input = "Plan a week in Lisbon"
        await r.vm.send()?.value
        let thread = try #require(r.vm.thread)
        ThreadActions.rename(thread, to: "Mine")
        gate.value = true
        await r.vm.titleTask?.value
        #expect(thread.title == "Mine")
        #expect(thread.titleSource == .user)
    }

    @Test func aChatTheUserRenamedBeforeIsNeverAskedAbout() async throws {
        let thread = ThreadRecord(title: "Mine")
        let r = try await rig(thread: thread)
        await say(r.vm, "Hello")
        #expect(thread.title == "Mine")
        let asked = r.apple.titleCalls.next()
        #expect(asked == 1, "no title request was made")
    }

    @Test func aCloudChatGetsItsTitleFromTheDeviceModelNotTheCloud() async throws {
        let r = try await rig(withCloud: true)
        await say(r.vm, "Plan a week in Lisbon")
        let cloud = try #require(r.cloud)
        let cloudAsked = cloud.titleCalls.next()
        let appleAsked = r.apple.titleCalls.next()
        #expect(cloudAsked == 1, "the cloud engine never saw a title request")
        #expect(appleAsked == 2, "Apple wrote it")
        #expect(r.vm.thread?.titleSource == .generated)
    }

    @Test func titlesAreOffUntilTheChatScreenTurnsThemOn() async throws {
        let r = try await rig()
        r.vm.generatesTitles = false
        await say(r.vm, "Plan a week in Lisbon")
        #expect(r.vm.thread?.titleSource == .firstMessage)
        let asked = r.apple.titleCalls.next()
        #expect(asked == 1)
    }
}
