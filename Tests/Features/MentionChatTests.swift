import Foundation
import SwiftData
import Testing

@testable import AnyRouter

/// Records the tool context of every request, like the chat screen's tool closure would receive it.
private final class ContextLog: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [ToolContext] = []
    var seen: [ToolContext] { lock.withLock { raw } }
    func add(_ context: ToolContext) { lock.withLock { raw.append(context) } }
}

@MainActor
struct MentionChatTests {
    private struct Rig {
        let vm: ChatViewModel
        let engine: ScriptedEngine
        let contexts: ContextLog
    }

    private let exa = MentionItem(kind: .plugin(sourceID: "exa"), title: "Exa", trailing: "Plugin", icon: .asset("Logo-exa"))
    private let deepWiki = MentionItem(kind: .plugin(sourceID: "deepwiki"), title: "DeepWiki", trailing: "Plugin", icon: .symbol("books.vertical"))

    private func rig() async throws -> Rig {
        var engine = ScriptedEngine(chunks: ["ok"])
        engine.models = [testModelWithTools()]
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let contexts = ContextLog()
        let vm = ChatViewModel(
            thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()),
            models: models, toolHost: { toolContext in
                contexts.add(toolContext)
                return StubToolHost()
            })
        return Rig(vm: vm, engine: engine, contexts: contexts)
    }

    @Test func choosingARowKeepsAChipAndTakesTheAtWordsOutOfTheField() async throws {
        let r = try await rig()
        r.vm.input = "what is swift @ex"
        r.vm.addMention(exa)
        #expect(r.vm.input == "what is swift")
        #expect(r.vm.mentions == [exa])
        // The same row twice is one chip.
        r.vm.addMention(exa)
        #expect(r.vm.mentions == [exa])
        r.vm.addMention(deepWiki)
        r.vm.removeMention(exa)
        #expect(r.vm.mentions == [deepWiki])
    }

    @Test func aMentionedPluginIsTheOnlySourceForTheNextRequestAndThenTheChipIsGone() async throws {
        let r = try await rig()
        r.vm.input = "what is swift @ex"
        r.vm.addMention(exa)
        await r.vm.send()?.value
        #expect(r.contexts.seen.map(\.forcedSourceIDs) == [["exa"]])
        #expect(r.vm.mentions.isEmpty)

        r.vm.input = "and now?"
        await r.vm.send()?.value
        #expect(r.contexts.seen.map(\.forcedSourceIDs) == [["exa"], []], "the next message is not forced")
    }

    @Test func theModelIsToldWhatWasAskedForButTheSavedMessageIsAsTyped() async throws {
        let r = try await rig()
        r.vm.input = "what is swift @ex"
        r.vm.addMention(exa)
        await r.vm.send()?.value
        #expect(r.engine.messagesSeen.lastTexts == ["what is swift\n\nUse the tools of Exa to answer this message."])
        #expect(r.vm.messages.first?.content == "what is swift")
    }

    @Test func aMentionWorksEvenWhenToolsAreSwitchedOffForTheChat() async throws {
        let r = try await rig()
        r.vm.setToolsEnabled(false)
        r.vm.input = "hello"
        await r.vm.send()?.value
        #expect(r.engine.toolsSeen.seen == [nil])

        r.vm.input = "look it up"
        r.vm.addMention(exa)
        await r.vm.send()?.value
        #expect(r.engine.toolsSeen.seen == [nil, ["search"]])
    }

    @Test func regeneratingDoesNotForceAnythingAgain() async throws {
        let r = try await rig()
        r.vm.input = "question"
        r.vm.addMention(exa)
        await r.vm.send()?.value
        await r.vm.regenerate()?.value
        #expect(r.contexts.seen.map(\.forcedSourceIDs) == [["exa"], []])
        #expect(r.engine.messagesSeen.lastTexts.last == "question")
    }
}
