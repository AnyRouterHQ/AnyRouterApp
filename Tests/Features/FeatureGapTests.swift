import Foundation
import SwiftData
import Testing
@testable import AnyRouter

private struct ThrowingEngine: ChatEngine {
    var source: ModelSource = .apple
    let error: Error

    func availableModels() async throws -> [ModelDescriptor] { [testModel()] }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}

@MainActor
struct ChatViewModelGapTests {
    private func make(
        _ engine: any ChatEngine, thread: ThreadRecord? = nil, context: ModelContext? = nil,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) async throws -> (vm: ChatViewModel, context: ModelContext) {
        let context = try context ?? ModelContext(ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let vm = ChatViewModel(thread: thread, context: context, registry: registry,
                               settings: AppSettings(defaults: testDefaults()), models: models, save: save)
        return (vm, context)
    }

    @Test func aCancellationErrorFromTheEngineIsNotShownAsAFailure() async throws {
        let (vm, _) = try await make(ThrowingEngine(error: CancellationError()))
        vm.input = "Hi"
        await vm.send()?.value
        #expect(vm.errorMessage == nil)
        #expect(vm.phase == .idle)
    }

    @Test func aFailedSaveIsReportedToTheUser() async throws {
        let (vm, _) = try await make(ScriptedEngine(chunks: ["ok"])) { _ in throw TestFailure(message: "disk full") }
        vm.input = "Hi"
        await vm.send()?.value
        #expect(vm.errorMessage == "Could not save the chat: disk full")
    }

    @Test func dismissingTheBannerClearsIt() async throws {
        let (vm, _) = try await make(ThrowingEngine(error: TestFailure(message: "boom")))
        vm.showError("boom")
        #expect(vm.errorMessage == "boom")
        vm.dismissError()
        #expect(vm.errorMessage == nil)
    }

    @Test func aFailedReplyThatTheUserStoppedIsNotAFailure() async throws {
        let (vm, _) = try await make(ThrowingEngine(error: URLError(.cancelled)))
        vm.input = "Hi"
        await vm.send()?.value
        #expect(vm.messages.last?.failure?.kind == .cancelled, "not stopped by the user: the reply says it stopped")
    }

    @Test func aFailedSendCanBeRetriedWithRegenerate() async throws {
        let engine = ScriptedEngine(failure: "offline")
        let (vm, _) = try await make(engine)
        vm.input = "Hi"
        await vm.send()?.value
        #expect(vm.messages.map(\.role) == [.user, .assistant])
        let failed = try #require(vm.messages.last)
        #expect(failed.failure == ReplyFailure(kind: .unknown, detail: "offline"))
        #expect(vm.canRegenerate)
        await vm.regenerate()?.value
        #expect(engine.calls.next() == 3, "send and retry each asked the engine once")
        #expect(vm.messages.map(\.role) == [.user, .assistant], "Retry replaces the failed reply instead of adding one")
        #expect(vm.messages.last?.id != failed.id)
        #expect(vm.errorMessage == nil)
    }

    @Test func regenerateNeedsAThreadAndSomethingToRegenerate() async throws {
        let (vm, _) = try await make(ScriptedEngine(chunks: ["x"]))
        #expect(!vm.canRegenerate)
        #expect(vm.regenerate() == nil)
    }

    @Test func regenerateCannotRunWhileStreaming() async throws {
        let (vm, _) = try await make(ScriptedEngine(chunks: ["a"], hangs: true))
        vm.input = "Hi"
        let task = try #require(vm.send())
        #expect(!vm.canRegenerate)
        #expect(vm.regenerate() == nil)
        vm.stop()
        await task.value
    }

    @Test func aThreadWithOnlyAReplyHasNothingToAnswerSoRegenerateDoesNothing() async throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let thread = ThreadRecord(title: "t")
        context.insert(thread)
        let reply = MessageRecord(role: .assistant, content: "orphan")
        context.insert(reply)
        reply.thread = thread
        let (vm, _) = try await make(ScriptedEngine(chunks: ["x"]), thread: thread, context: context)
        #expect(vm.canRegenerate)
        #expect(vm.regenerate() == nil)
        #expect(vm.messages.isEmpty)
    }

    @Test func sendInAnExistingThreadDoesNotCreateAnother() async throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let thread = ThreadRecord(title: "Existing")
        context.insert(thread)
        let (vm, _) = try await make(ScriptedEngine(chunks: ["ok"]), thread: thread, context: context)
        let created = Flag()
        vm.onThreadCreated = { _ in created.value = true }
        vm.input = "Hi"
        await vm.send()?.value
        #expect(!created.value)
        #expect(vm.thread === thread)
        #expect(thread.modelID == "apple/foundation")
        #expect(try context.fetch(FetchDescriptor<ThreadRecord>()).count == 1)
    }
}

@MainActor
struct ModelStoreGapTests {
    @Test func restoringAThreadsModelSelectsItAndPersistsTheChoice() async {
        let defaults = testDefaults()
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(models: [testModel(id: "a"), testModel(id: "b")]))
        let store = ModelStore(registry: registry, defaults: defaults)
        await store.refresh()
        #expect(store.selected?.id == "a")
        store.select(modelID: "b")
        #expect(store.selected?.id == "b")
        #expect(defaults.string(forKey: "models.selectedID") == "b")
        store.select(modelID: nil)
        #expect(store.selected?.id == "b")
        #expect(!store.isLoading)
    }
}

struct PickerTitleTests {
    @Test func sectionsHaveFriendlyTitlesAndStableIDs() {
        let titles = [PickerSection.Kind.apple, .anyrouter, .local].map { PickerSection(kind: $0, models: []).title }
        #expect(titles == ["Apple Intelligence", "AnyRouter", "On this device"])
        #expect(PickerSection(kind: .local, models: []).id == "local")
        #expect(PickerSection(kind: .provider("openai"), models: []).title == "OpenAI")
        #expect(PickerSection(kind: .provider("openai"), models: []).id == "provider/openai")
    }

    @Test func localSubtitleWithoutSizeShowsOnlyTheFormat() {
        #expect(ModelPickerLogic.subtitle(for: testModel(source: .gguf)) == "GGUF")
        #expect(ModelPickerLogic.subtitle(for: testModel(source: .mlx)) == "MLX")
        var mlx = testModel(source: .mlx)
        mlx.sizeBytes = 2_000_000_000
        #expect(ModelPickerLogic.subtitle(for: mlx).hasPrefix("MLX · "))
    }
}

@MainActor
struct ShellGapTests {
    @Test func togglingTheSidebarFlipsIt() {
        let shell = ShellModel()
        shell.toggleSidebar()
        #expect(shell.isSidebarOpen)
        shell.toggleSidebar()
        #expect(!shell.isSidebarOpen)
    }

    @Test func openingChatDismissesTheHubAndClosesTheSidebarOnlyWhenAsked() {
        let shell = ShellModel()
        shell.isSidebarOpen = true
        shell.open(.hub, closeSidebar: false)
        #expect(shell.isHubPresented && shell.isSidebarOpen)
        shell.open(.chat, closeSidebar: true)
        #expect(!shell.isHubPresented && !shell.isSidebarOpen)
    }
}

struct SettingsGapTests {
    @Test func everyLicenseNoticeHasAStableID() {
        #expect(LicenseNotice.all.map(\.id) == LicenseNotice.all.map(\.name))
        #expect(Set(LicenseNotice.all.map(\.id)).count == LicenseNotice.all.count)
    }
}

struct TitleGapTests {
    @Test func emptyTextGivesTheDefaultTitle() {
        #expect(ThreadListLogic.title(fromFirstMessage: "") == "New chat")
    }
}
