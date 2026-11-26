import Foundation
import SwiftData
import Testing

@testable import AnyRouter

private final class SearchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [(query: String, context: ToolContext)] = []
    var queries: [String] { lock.withLock { raw.map(\.query) } }
    var contexts: [ToolContext] { lock.withLock { raw.map(\.context) } }
    func add(_ query: String, _ context: ToolContext) { lock.withLock { raw.append((query, context)) } }
}

@MainActor
struct PreSearchChatTests {
    private struct Rig {
        let vm: ChatViewModel
        let engine: ScriptedEngine
        let log: SearchLog
    }

    private let answer = ToolResult(
        callID: "x", name: "web_search_exa",
        text: "Title: Swift 6.3 released\nURL: https://swift.example/6-3\nHighlights:\nSwift 6.3 shipped today.", isError: false)

    private func rig(
        source: ModelSource = .gguf, on: Bool = true, answer: ToolResult?, online: Bool = true
    ) async throws -> Rig {
        let model = testModel(id: "\(source.rawValue)/test", source: source)
        var engine = ScriptedEngine(chunks: ["ok"])
        engine.source = source
        engine.models = [model]
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let log = SearchLog()
        let searcher = PreSearcher(isOn: { _ in on }, search: { query, context in
            log.add(query, context)
            return answer
        })
        let vm = ChatViewModel(
            thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()),
            models: models, isOnline: { online }, webSearch: searcher)
        return Rig(vm: vm, engine: engine, log: log)
    }

    private func send(_ text: String, on r: Rig) async {
        r.vm.input = text
        await r.vm.send()?.value
    }

    @Test func aQuestionAboutNowSearchesAndTheModelGetsTheResultsInFrontOfIt() async throws {
        let r = try await rig(answer: answer)
        await send("What is the latest Swift release?", on: r)
        #expect(r.log.queries == ["What is the latest Swift release?"])
        let expected = try #require(WebGrounding.context(for: WebGrounding.parse(answer.text)))
        #expect(r.engine.messagesSeen.lastTexts == [expected + "\n\nQuestion: What is the latest Swift release?"])
        #expect(expected.contains("https://swift.example/6-3"))
        // The chat keeps the question as typed.
        #expect(r.vm.messages.first?.content == "What is the latest Swift release?")
    }

    @Test func theReplyShowsTheSameSearchedTheWebRowAsAToolCall() async throws {
        let r = try await rig(answer: answer)
        await send("What is the latest Swift release?", on: r)
        let step = try #require(r.vm.messages.last?.toolSteps.first)
        #expect(r.vm.messages.last?.toolSteps.count == 1)
        #expect(step.call.name == "web_search")
        #expect(step.result?.text == answer.text)
        #expect(step.result?.callID == step.call.id)
        #expect(ToolRowLogic.title(for: step) == "Searched the web for “What is the latest Swift release?”")
    }

    @Test func aQuestionTheModelKnowsIsNotSearched() async throws {
        let r = try await rig(answer: answer)
        await send("Explain how recursion works", on: r)
        #expect(r.log.queries.isEmpty)
        #expect(r.engine.messagesSeen.lastTexts == ["Explain how recursion works"])
        #expect(r.vm.messages.last?.toolSteps.isEmpty == true)
    }

    @Test func modelsWithAToolLoopAreLeftToTheirOwnTools() async throws {
        let apple = try await rig(source: .apple, answer: answer)
        await send("What is the latest Swift release?", on: apple)
        #expect(apple.log.queries.isEmpty)
        let cloud = try await rig(source: .anyrouter, answer: answer)
        await send("What is the latest Swift release?", on: cloud)
        #expect(cloud.log.queries.isEmpty)
    }

    @Test func mlxModelsGetTheSearchToo() async throws {
        let r = try await rig(source: .mlx, answer: answer)
        await send("bitcoin price today", on: r)
        #expect(r.log.queries == ["bitcoin price today"])
    }

    @Test func withWebSearchOffNothingIsSearchedAndNoRowShows() async throws {
        let off = try await rig(on: false, answer: answer)
        await send("What is the latest Swift release?", on: off)
        #expect(off.log.queries.isEmpty)
        #expect(off.vm.messages.last?.toolSteps.isEmpty == true)

        let toolsOff = try await rig(answer: answer)
        toolsOff.vm.setToolsEnabled(false)
        await send("What is the latest Swift release?", on: toolsOff)
        #expect(toolsOff.log.queries.isEmpty)
    }

    @Test func aSearchThatCannotRunRemovesItsRowAndAsksTheModelAsTyped() async throws {
        let r = try await rig(answer: nil)
        await send("What is the latest Swift release?", on: r)
        #expect(r.log.queries.count == 1)
        #expect(r.vm.messages.last?.toolSteps.isEmpty == true)
        #expect(r.engine.messagesSeen.lastTexts == ["What is the latest Swift release?"])
    }

    @Test func aFailedSearchShowsAFailedRowAndAddsNoContext() async throws {
        let failed = ToolResult(callID: "x", name: "web_search_exa", text: "rate limited", isError: true)
        let r = try await rig(answer: failed)
        await send("What is the latest Swift release?", on: r)
        let step = try #require(r.vm.messages.last?.toolSteps.first)
        #expect(step.result?.isError == true)
        #expect(r.engine.messagesSeen.lastTexts == ["What is the latest Swift release?"])
    }

    @Test func anAnswerWithNoReadableResultsAddsNoContext() async throws {
        let empty = ToolResult(callID: "x", name: "web_search_exa", text: "No results found.", isError: false)
        let r = try await rig(answer: empty)
        await send("What is the latest Swift release?", on: r)
        #expect(r.engine.messagesSeen.lastTexts == ["What is the latest Swift release?"])
        #expect(r.vm.messages.last?.toolSteps.count == 1)
    }

    @Test func offlineTheChatSaysSoAndDoesNotSearch() async throws {
        let r = try await rig(answer: answer, online: false)
        await send("What is the latest Swift release?", on: r)
        #expect(r.log.queries.isEmpty)
        #expect(r.vm.offlineToolNote == OfflineLogic.toolNote)
        #expect(r.engine.messagesSeen.lastTexts == ["What is the latest Swift release?"])
    }

    @Test func theSearchContextCarriesWhatTheUserWroteForTheLongPassageCheck() async throws {
        let r = try await rig(answer: answer)
        await send("What is the latest Swift release?", on: r)
        let context = try #require(r.log.contexts.first)
        #expect(context.userTexts.contains("What is the latest Swift release?"))
        #expect(context.modelSource == .gguf)
    }
}
