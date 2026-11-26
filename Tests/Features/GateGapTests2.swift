import Foundation
import SwiftData
import Testing
@testable import AnyRouter

struct BundleInfoTests {
    @Test func missingKeysFallBackAndPresentKeysWin() {
        #expect(Bundle.main.infoString("NoSuchInfoKey", default: "fallback") == "fallback")
        #expect(Bundle.main.infoString("CFBundleIdentifier", default: "fallback") != "fallback")
        #expect(Bundle(path: makeTempDirectory().path)?.infoString("CFBundleVersion", default: "none") == "none")
    }
}

struct AnyRouterStatusTests {
    @Test func statusOfHTTPAndOtherResponses() {
        let http = HTTPURLResponse(url: URL(string: "https://a.test")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        let other = URLResponse(url: URL(string: "https://a.test")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(AnyRouterError.status(of: http) == 204)
        #expect(AnyRouterError.status(of: other) == 0)
    }

    @Test func keychainItemsDecodeOnlyFromUTF8Data() {
        #expect(SystemKeychain.string(from: Data("sk-ar-1".utf8) as CFTypeRef) == "sk-ar-1")
        #expect(SystemKeychain.string(from: nil) == nil)
        #expect(SystemKeychain.string(from: Data([0xFF, 0xFE]) as CFTypeRef) == nil)
        #expect(SystemKeychain.string(from: "text" as CFTypeRef) == nil)
    }
}

struct CatalogEdgeTests {
    @Test func aGGUFEntryWithoutAFileStillHasAnID() {
        let entry = CatalogEntry(repo: "org/m", format: .gguf, file: nil, title: "x")
        #expect(entry.id == "gguf/org/m/")
        #expect(throws: LocalModelError.notFound("org/m")) { try RepoFiles.downloadPlan(for: entry, files: []) }
    }

    @Test func settingsSavedBeforeAFieldExistedStillLoad() throws {
        let settings = try JSONDecoder().decode(CatalogSettings.self, from: Data("{}".utf8))
        #expect(settings == CatalogSettings())
        #expect(!settings.useDevelopmentCatalog)
    }

    @Test func fileNamesAreEscapedForTheDownloadURL() {
        let url = HuggingFaceAPI().resolveURL(repo: "org/m", revision: "main", path: "a b/é?.gguf")
        #expect(url.absoluteString == "https://huggingface.co/org/m/resolve/main/a%20b/%C3%A9%3F.gguf")
    }

    @Test func resumeDataSitsNextToItsPartialFile() {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let url = storage.resumeDataURL(forEntryID: "mlx/org/m", path: "weights/a.safetensors")
        #expect(url.lastPathComponent == "a.safetensors.resume")
        #expect(url.deletingLastPathComponent() == storage.partialFileURL(forEntryID: "mlx/org/m", path: "weights/a.safetensors").deletingLastPathComponent())
    }

    @Test func pendingJobsComeBackInIDOrder() throws {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let b = sampleMLX(repo: "org/b"), a = sampleMLX(repo: "org/a")
        for entry in [b, a] { try storage.writeJob(DownloadJobRecord(entry: entry, files: [HFFile(path: "config.json", size: 2)])) }
        #expect(storage.pendingJobs().map(\.entry.id) == [a.id, b.id])
    }

    @Test func aMissingPartialFileIsASizeError() {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let record = DownloadJobRecord(entry: sampleMLX(), files: [HFFile(path: "config.json", size: 2)])
        #expect(throws: (any Error).self) { try ModelInstaller.verifyAndInstall(record, storage: storage) }
    }
}

struct PickerEdgeTests {
    private func cloud(_ id: String, summary: String? = nil) -> ModelDescriptor {
        var model = testModel(id: id, source: .anyrouter)
        model.summary = summary
        return model
    }

    @Test func aCloudModelWithoutAProviderLandsInOther() {
        let sections = ModelPickerLogic.sections(models: [cloud("anyrouter/loner")], query: "")
        #expect(sections.contains { $0.models.map(\.id) == ["anyrouter/loner"] })
        #expect(ModelPickerLogic.subtitle(for: cloud("anyrouter/loner")) == "Cloud")
    }

    @Test func providerGroupsAreSortedByTheirDisplayTitle() {
        let models = [cloud("anyrouter/x-ai/grok"), cloud("anyrouter/anthropic/claude"), cloud("anyrouter/openai/gpt")]
        let kinds = ModelPickerLogic.sections(models: models, query: "").map(\.id)
        #expect(kinds.count == 4, "the empty router group stays, then one group per provider")
        let titles = ModelPickerLogic.sections(models: models, query: "").dropFirst().map(\.title)
        #expect(titles == titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test func routerSubtitleUsesItsSummaryOrJustAnyRouter() {
        #expect(ModelPickerLogic.subtitle(for: cloud("anyrouter/anyrouter/coding")) == "AnyRouter")
        #expect(ModelPickerLogic.subtitle(for: cloud("anyrouter/anyrouter/coding", summary: "Best for code. Uses many models.")) == "Best for code")
        #expect(ModelPickerLogic.subtitle(for: cloud(ModelDescriptor.autoRouterID)) == ModelPickerLogic.autoSubtitle)
    }

    @Test func shortSummaryHandlesEmptyAndLongText() {
        #expect(ModelPickerLogic.shortSummary("") == "")
        #expect(ModelPickerLogic.shortSummary("One line.\nSecond line.") == "One line")
        #expect(ModelPickerLogic.shortSummary(String(repeating: "x", count: 120)).count == 80)
    }
}

@MainActor
struct ChatViewModelEdgeTests {
    private func make(
        models: [ModelDescriptor] = [testModel()], save: @escaping (ModelContext) throws -> Void = { try $0.save() },
        thread: ThreadRecord? = nil, context: ModelContext? = nil
    ) async throws -> ChatViewModel {
        let context = try context ?? ModelContext(ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(models: models, chunks: ["ok"]))
        let store = ModelStore(registry: registry, defaults: testDefaults())
        await store.refresh()
        return ChatViewModel(thread: thread, context: context, registry: registry,
                             settings: AppSettings(defaults: testDefaults()), models: store, save: save)
    }

    @Test func sendingIsAllowedOnlyWithTextAndWhileIdle() async throws {
        let vm = try await make()
        #expect(!vm.canSend)
        vm.input = "  hi  "
        #expect(vm.canSend)
    }

    @Test func aModelWithToolsRunsWithoutAToolHostToo() async throws {
        var withTools = testModel()
        withTools.capabilities = ["chat", "tools"]
        let vm = try await make(models: [withTools])
        vm.input = "hi"
        await vm.send()?.value
        #expect(vm.messages.last?.content == "ok")
    }

    @Test func choosingAModelInAThreadSavesItAndReportsASaveFailure() async throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let thread = ThreadRecord(title: "t")
        context.insert(thread)
        let vm = try await make(save: { _ in throw TestFailure(message: "disk full") }, thread: thread, context: context)
        vm.choose(testModel(id: "apple/foundation"))
        #expect(thread.modelID == "apple/foundation")
        #expect(vm.errorMessage == "Could not save the chat: disk full")
    }

    @Test func choosingAModelBeforeTheFirstMessageOnlyRemembersIt() async throws {
        let vm = try await make()
        vm.choose(testModel(id: "apple/foundation"))
        #expect(vm.thread == nil)
        #expect(vm.errorMessage == nil)
    }
}

@MainActor
struct PresetBundleTests {
    @Test func aMissingPresetFileGivesAnEmptyListNotACrash() {
        #expect(PresetStore.bundledOrEmpty(bundle: Bundle(path: makeTempDirectory().path)).isEmpty)
        #expect(!PresetStore.bundledOrEmpty().isEmpty)
    }
}
