import Foundation
import Testing
@testable import AnyRouter

private final class FixtureAnchor {}

struct LocalModelDescriptorsTests {
    private func install(_ entry: CatalogEntry, in storage: LocalModelStorage, path: String, bytes: String = "data") throws {
        let url = storage.partialFileURL(forEntryID: entry.id, path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes.utf8).write(to: url)
        try ModelInstaller.verifyAndInstall(
            DownloadJobRecord(entry: entry, files: [HFFile(path: path, size: Int64(bytes.utf8.count))]), storage: storage)
    }

    @Test func listsOnlyInstalledModelsOfTheAskedFormat() throws {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let gguf = sampleGGUF(repo: "org/a-GGUF", file: "a-Q4_K_M.gguf", title: "Alpha")
        let mlx = sampleMLX(repo: "org/b-4bit", title: "Beta")
        try install(gguf, in: storage, path: "a-Q4_K_M.gguf")
        try install(mlx, in: storage, path: "model.safetensors")

        let result = LocalModelDescriptors.installed(format: .gguf, storage: storage, catalog: [gguf, mlx])
        #expect(result.map(\.id) == [gguf.id])
        #expect(result.first?.source == .gguf)
        #expect(result.first?.isInstalled == true)
        #expect(result.first?.displayName == "Alpha")
        #expect(result.first?.sizeBytes == 4, "size is what is on disk")
    }

    /// Agent v2 U4: an MLX model's compaction window and its KV cache are one number, the planned context, so the cache
    /// never rotates the oldest tokens (the system prompt first) out before the chat compacts.
    @Test func anMLXModelsWindowIsItsKVCacheSize() throws {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let entry = CatalogEntry(
            repo: "org/Planned-4bit", format: .mlx, title: "Planned", sizeBytes: 2_000_000_000, contextLength: 131_072,
            memory: CatalogMemory(fullKVBytesPerToken: 114_688))
        try install(entry, in: storage, path: "model.safetensors")
        let roomy = DeviceMemory(budgetBytes: 6_000_000_000, physicalBytes: 8_000_000_000)
        let tight = DeviceMemory(budgetBytes: 3_400_000_000, physicalBytes: 6_000_000_000)
        for memory in [roomy, tight] {
            let model = try #require(LocalModelDescriptors.installed(format: .mlx, storage: storage, catalog: [entry], memory: memory).first)
            let planned = FitPlanner.estimate(try #require(entry.memoryProfile), memory: memory).context
            #expect(model.contextLength == planned)
            #expect(CompactionLogic.window(for: model) == CompactionLogic.mlxKVSize(for: model))
            #expect(CompactionLogic.mlxKVSize(for: model) == planned)
        }
        let unknown = ModelDescriptor(id: "mlx/x", source: .mlx, displayName: "x", contextLength: nil, capabilities: ["chat"],
                                      sizeBytes: nil, isInstalled: true)
        #expect(CompactionLogic.mlxKVSize(for: unknown) == 4096)
    }

    @Test func aModelUnknownToTheCatalogIsNamedAfterItsRepo() throws {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let entry = sampleMLX(repo: "someone/Custom-4bit")
        try install(entry, in: storage, path: "model.safetensors")
        let result = LocalModelDescriptors.installed(format: .mlx, storage: storage, catalog: [])
        #expect(result.first?.displayName == "Custom-4bit")
        #expect(result.first?.source == .mlx)
    }

    @Test func ggufNamesCarryTheQuantization() {
        var entry = sampleGGUF(title: "Qwen3 1.7B")
        entry.quantization = "Q4_K_M"
        #expect(entry.descriptor(isInstalled: false).displayName == "Qwen3 1.7B (Q4_K_M)")
        #expect(entry.descriptor(isInstalled: false).id == entry.id)
    }
}

struct GGUFEngineTests {
    private let entry = CatalogEntry(
        repo: "ggml-org/tiny-llamas", format: .gguf, file: "stories260K.gguf", title: "Tiny", quantization: "F32")

    private func makeEngine(installFixture: Bool, loadLog: DiagnosticsStore? = nil) throws -> GGUFEngine {
        let storage = LocalModelStorage(root: makeTempDirectory())
        if installFixture {
            let source = try #require(
                Bundle(for: FixtureAnchor.self).url(forResource: "stories260K", withExtension: "gguf"),
                "fixture missing from the test bundle")
            let target = storage.partialFileURL(forEntryID: entry.id, path: "stories260K.gguf")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
            let size = try #require(try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber).int64Value
            try ModelInstaller.verifyAndInstall(
                DownloadJobRecord(entry: entry, files: [HFFile(path: "stories260K.gguf", size: size)]), storage: storage)
        }
        let catalog = CatalogService(
            bundled: { CatalogDocument(schemaVersion: 1, updatedAt: nil, models: []) },
            cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        return GGUFEngine(storage: storage, catalog: catalog, loadLog: loadLog)
    }

    private func collect(_ engine: GGUFEngine, prompt: String, params: GenerationParams) async throws -> [ChatDelta] {
        let model = entry.descriptor(isInstalled: true)
        var deltas: [ChatDelta] = []
        for try await delta in engine.stream(model: model, messages: [ChatMessage(role: .user, content: prompt)], params: params) {
            deltas.append(delta)
        }
        return deltas
    }

    private func text(_ deltas: [ChatDelta]) -> String {
        deltas.compactMap { delta -> String? in
            if case .text(let piece) = delta { return piece }
            return nil
        }.joined()
    }

    /// A phone test of a big model needs evidence even when the system ends the app: each load leaves one record with
    /// its steps, and a reply on weights already loaded adds none.
    @Test(.timeLimit(.minutes(2)))
    func aLoadAndItsFirstReplyLeaveOneRecordOfTheirSteps() async throws {
        let store = DiagnosticsStore(directory: makeTempDirectory().appending(path: "Diagnostics"))
        let engine = try makeEngine(installFixture: true, loadLog: store)
        var params = GenerationParams()
        params.temperature = 0
        params.maxTokens = 8
        _ = try await collect(engine, prompt: "Once upon a time", params: params)
        _ = try await collect(engine, prompt: "Once upon a time", params: params)
        let records = store.list()
        #expect(records.map(\.kind) == [.modelLoad])
        let trace = try #require(records.first.flatMap(store.modelLoadTrace(of:)))
        #expect(trace.model == "stories260K.gguf", "the record names the file, never the repo")
        #expect(trace.stages.map(\.step) == [.started, .mapped, .contextReady, .firstToken, .finished])
        #expect(trace.stages[1].note?.contains("token context") == true)
    }

    @Test(.timeLimit(.minutes(2)))
    func theFirstReplyAfterAWarmUpAddsToTheWarmUpsRecord() async throws {
        let store = DiagnosticsStore(directory: makeTempDirectory().appending(path: "Diagnostics"))
        let engine = try makeEngine(installFixture: true, loadLog: store)
        await engine.warm(model: entry.descriptor(isInstalled: true))
        var params = GenerationParams()
        params.temperature = 0
        params.maxTokens = 4
        _ = try await collect(engine, prompt: "Hi", params: params)
        let records = store.list()
        #expect(records.count == 1)
        let trace = try #require(records.first.flatMap(store.modelLoadTrace(of:)))
        #expect(trace.stages.map(\.step) == [.started, .mapped, .contextReady, .firstToken, .finished])
    }

    @Test func engineListsTheInstalledGGUFModel() async throws {
        let engine = try makeEngine(installFixture: true)
        let models = try await engine.availableModels()
        #expect(models.map(\.id) == [entry.id])
        #expect(engine.source == .gguf)
    }

    @Test func streamingAModelThatIsNotDownloadedFailsWithAClearError() async throws {
        let engine = try makeEngine(installFixture: false)
        await #expect(throws: GGUFError.modelNotInstalled(entry.id)) {
            _ = try await collect(engine, prompt: "hi", params: GenerationParams())
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func realLlamaCppRunStreamsTextThenUsageThenDone() async throws {
        let engine = try makeEngine(installFixture: true)
        var params = GenerationParams()
        params.temperature = 0
        params.maxTokens = 12
        let deltas = try await collect(engine, prompt: "Once upon a time", params: params)

        guard case .done(let reason)? = deltas.last else {
            Issue.record("stream must end with .done, got \(deltas)")
            return
        }
        #expect(reason == "length" || reason == "stop")
        let usage = deltas.compactMap { delta -> (Int, Int)? in
            if case .usage(let usage) = delta { return (usage.input, usage.output) } else { return nil }
        }
        #expect(usage.count == 1)
        #expect((usage.first?.0 ?? 0) > 0, "prompt tokens are counted")
        #expect((usage.first?.1 ?? 0) <= 12, "maxTokens is respected")
        #expect(!text(deltas).isEmpty || reason == "stop")
    }

    @Test(.timeLimit(.minutes(2)))
    func greedyDecodingGivesTheSameAnswerTwice() async throws {
        let engine = try makeEngine(installFixture: true)
        var params = GenerationParams()
        params.temperature = 0
        params.maxTokens = 16
        let first = text(try await collect(engine, prompt: "The little girl", params: params))
        let second = text(try await collect(engine, prompt: "The little girl", params: params))
        #expect(first == second)
    }

    @Test(.timeLimit(.minutes(2)))
    func droppingTheStreamStopsGenerationAndFreesTheEngineForTheNextChat() async throws {
        let engine = try makeEngine(installFixture: true)
        var long = GenerationParams()
        long.temperature = 0.8
        long.maxTokens = 400
        let model = entry.descriptor(isInstalled: true)
        let messages = [ChatMessage(role: .user, content: "Tell a long story.")]
        for try await _ in engine.stream(model: model, messages: messages, params: long) {
            break // consumer walks away after the first delta
        }
        var short = GenerationParams()
        short.temperature = 0
        short.maxTokens = 4
        let deltas = try await collect(engine, prompt: "Hi", params: short)
        guard case .done? = deltas.last else {
            Issue.record("the second chat must complete after the first was dropped")
            return
        }
    }
}
