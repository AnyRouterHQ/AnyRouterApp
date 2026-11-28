import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// After a reply on Apple's model the chat keeps what the user said about themselves (agent design 2.3, unit M6).
@MainActor
struct MemoryExtractionChatTests {
    private final class FakeExtractor: MemoryExtracting, @unchecked Sendable {
        private let lock = NSLock()
        private var raw: [String] = []
        let answer: [String]

        init(_ answer: [String]) { self.answer = answer }

        var asked: [String] { lock.withLock { raw } }

        func statements(in message: String) async -> [String] {
            lock.withLock { raw.append(message) }
            return answer
        }
    }

    @MainActor private struct Rig {
        let context: ModelContext
        let settings: AppSettings
        let engine: ScriptedEngine
        let chat: ChatViewModel
        let extractor: FakeExtractor
        var store: MemoryStore { MemoryStore(context: context) }

        func send(_ text: String) async {
            chat.input = text
            await chat.send()?.value
            await chat.extractionTask?.value
        }
    }

    private static let said = "I'm training for a marathon in Hue"

    private func rig(
        source: ModelSource = .apple, id: String = "apple/foundation", answer: [String] = ["I'm training for a marathon", "I live in Hue"],
        failure: String? = nil
    ) async throws -> Rig {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let engine = ScriptedEngine(source: source, models: [testModel(id: id, source: source)], chunks: ["ok"], failure: failure)
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let settings = AppSettings(defaults: testDefaults())
        let chat = ChatViewModel(thread: nil, context: context, registry: registry, settings: settings, models: models)
        let extractor = FakeExtractor(answer)
        chat.extractor = extractor
        return Rig(context: context, settings: settings, engine: engine, chat: chat, extractor: extractor)
    }

    @Test func whatTheModelFindsIsSavedOnTheDeviceWithRowsAndUndo() async throws {
        let r = try await rig(answer: ["I'm training for a marathon", "I live in Hue", "Totally invented"])
        await r.send(Self.said)
        #expect(r.extractor.asked == [Self.said])
        #expect(r.engine.messagesSeen.lastTexts == [Self.said], "the extraction comes after the reply and changes no request")
        let reply = try #require(r.chat.messages.last)
        #expect(reply.memoryUpdates.map(\.text) == ["I'm training for a marathon", "I live in Hue"])
        #expect(reply.memoryUpdates.allSatisfy { $0.outcome == .saved })
        let items = try r.store.all()
        #expect(items.count == 2 && items.allSatisfy { $0.origin == .extracted && $0.scope == .deviceOnly && $0.kind == .fact })
        #expect(items.allSatisfy { $0.sourceMessageID == r.chat.messages.first?.id })

        try r.store.undo(reply.memoryUpdates[0], on: reply)
        #expect(try r.store.all().map(\.text) == ["I live in Hue"])
        #expect(reply.memoryUpdates.map(\.outcome) == [.undone, .saved])
    }

    @Test func rememberThatSavesAndTheModelIsNotAsked() async throws {
        let r = try await rig()
        await r.send("Remember that I'm vegetarian")
        #expect(r.extractor.asked.isEmpty)
        #expect(r.chat.messages.last?.memoryUpdates.map(\.text) == ["I'm vegetarian"])
        #expect(try r.store.all().count == 1)
    }

    @Test func aRepeatOrNothingFoundAddsNoRow() async throws {
        let r = try await rig(answer: ["I live in Hue"])
        try r.store.add("I live in Hue", kind: .fact)
        await r.send(Self.said)
        #expect(r.extractor.asked == [Self.said])
        #expect(r.chat.messages.last?.memoryUpdates.isEmpty == true)
        #expect(try r.store.all().count == 1)

        let none = try await rig(answer: [])
        await none.send(Self.said)
        #expect(none.chat.messages.last?.memoryUpdates.isEmpty == true)
    }

    @Test func nothingIsAskedForAQuestionOrWithSavingOffOrMemoryOff() async throws {
        let question = try await rig()
        await question.send("Hello")
        await question.send("What should I cook tonight?")
        #expect(question.extractor.asked.isEmpty)

        let manual = try await rig()
        manual.settings.saveMemoriesAutomatically = false
        await manual.send(Self.said)
        #expect(manual.extractor.asked.isEmpty)

        let off = try await rig()
        off.settings.useMemory = false
        await off.send(Self.said)
        #expect(off.extractor.asked.isEmpty)

        let thisChatOff = try await rig()
        thisChatOff.chat.setMemoryOff(true)
        await thisChatOff.send(Self.said)
        #expect(thisChatOff.extractor.asked.isEmpty)
    }

    @Test func nothingIsAskedOnGGUFMLXOrCloudChatsOrAfterAFailedReply() async throws {
        for (source, id) in [(ModelSource.gguf, "gguf/test"), (.mlx, "mlx/test"), (.anyrouter, "anyrouter/test")] {
            let r = try await rig(source: source, id: id)
            await r.send(Self.said)
            #expect(r.extractor.asked.isEmpty, "\(id)")
            #expect(try r.store.all().isEmpty)
        }
        let failed = try await rig(failure: "boom")
        await failed.send(Self.said)
        #expect(failed.extractor.asked.isEmpty)
    }

    @Test func withoutAnExtractorNothingRuns() async throws {
        let r = try await rig()
        r.chat.extractor = nil
        await r.send(Self.said)
        #expect(r.chat.extractionTask == nil)
        #expect(try r.store.all().isEmpty)
    }
}
