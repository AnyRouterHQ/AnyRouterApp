import Foundation
import Testing
@testable import AnyRouter

private final class ResponsivenessFixtureAnchor {}

/// The hang guard: while a local model loads and answers, the main actor must keep running. A job that blocks the main
/// actor (a load, a hash, a disk scan) shows up here as a long gap between ticks, long before it freezes a phone.
@MainActor
struct MainActorResponsivenessTests {
    private let entry = CatalogEntry(
        repo: "ggml-org/tiny-llamas", format: .gguf, file: "stories260K.gguf", title: "Tiny", quantization: "F32")

    /// A load that blocks the main actor stalls it for seconds. This is generous so a busy CI runner does not fail the
    /// test: a frame is 16 ms, the app's own watchdog flags 250 ms.
    private static let allowedGap: Duration = .milliseconds(750)

    /// Runs `work` off the main actor while the main actor ticks every 10 ms. Returns the longest gap between ticks.
    private func longestGap(while work: @escaping @Sendable () async throws -> Void) async throws -> Duration {
        let clock = ContinuousClock()
        let finished = Flag()
        let worker = Task.detached {
            defer { finished.value = true }
            try await work()
        }
        var last = clock.now
        var longest = Duration.zero
        while !finished.value {
            try await Task.sleep(for: .milliseconds(10))
            let now = clock.now
            longest = max(longest, now - last)
            last = now
        }
        try await worker.value
        return longest
    }

    private func installedEngine() throws -> GGUFEngine {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let source = try #require(
            Bundle(for: ResponsivenessFixtureAnchor.self).url(forResource: "stories260K", withExtension: "gguf"),
            "fixture missing from the test bundle")
        let target = storage.partialFileURL(forEntryID: entry.id, path: "stories260K.gguf")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: target)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber).int64Value
        try ModelInstaller.verifyAndInstall(
            DownloadJobRecord(entry: entry, files: [HFFile(path: "stories260K.gguf", size: size)]), storage: storage)
        let tinyEntry = entry
        let catalog = CatalogService(
            bundled: { CatalogDocument(schemaVersion: 2, updatedAt: nil, models: [tinyEntry]) },
            cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        return GGUFEngine(storage: storage, catalog: catalog)
    }

    @Test func theMainActorKeepsRunningWhileAModelLoadsAndAnswers() async throws {
        let engine = try installedEngine()
        let model = entry.descriptor(isInstalled: true)
        var settings = GenerationParams()
        settings.temperature = 0
        settings.maxTokens = 48
        let params = settings
        let gap = try await longestGap {
            // First call loads the weights and creates the context; the second reuses them.
            for _ in 0..<2 {
                for try await _ in engine.stream(
                    model: model, messages: [ChatMessage(role: .user, content: "Once upon a time")], params: params) {}
            }
        }
        #expect(gap < Self.allowedGap, "the main actor was blocked for \(gap) while a model loaded")
    }

    @Test func listingModelsAndWarmingTheSelectedOneNeverBlocksTheMainActor() async throws {
        let engine = try installedEngine()
        let registry = EngineRegistry()
        registry.register(engine)
        let model = entry.descriptor(isInstalled: true)
        let gap = try await longestGap {
            await engine.warm(model: model)
            #expect(await engine.loadedModelID() == model.id)
        }
        #expect(gap < Self.allowedGap, "warming blocked the main actor for \(gap)")
        let listed = await registry.allModels()
        #expect(listed.map(\.id) == [model.id])
    }

    @Test func aWarmUpDuringAGenerationDoesNothingAndLoadsAfterwards() async throws {
        let engine = try installedEngine()
        let model = entry.descriptor(isInstalled: true)
        await engine.gate.acquire() // a generation is running
        await engine.warm(model: model)
        #expect(await engine.loadedModelID() == nil, "the warm-up must not compete with a chat")
        await engine.gate.release()
        await engine.warm(model: model)
        #expect(await engine.loadedModelID() == model.id)
        #expect(await engine.gate.tryAcquire(), "the warm-up gave the gate back")
    }

    @Test func theGateIsTakenOnlyWhenFree() async {
        let gate = GenerationGate()
        #expect(await gate.tryAcquire())
        #expect(await !gate.tryAcquire(), "busy")
        await gate.release()
        #expect(await gate.tryAcquire(), "free again after release")
    }

    @Test func deletingAModelFreesItsWeightsOnlyWhenTheyAreItsOwn() async throws {
        let engine = try installedEngine()
        let model = entry.descriptor(isInstalled: true)
        await engine.warm(model: model)
        await engine.unload(modelID: "gguf/other/model/x.gguf")
        #expect(await engine.loadedModelID() == model.id, "another model's deletion must not unload this one")
        await engine.unload(modelID: model.id)
        #expect(await engine.loadedModelID() == nil)
    }
}
