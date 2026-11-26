import Foundation
import Testing
@testable import AnyRouter

struct FakeEngine: ChatEngine {
    let source: ModelSource
    var models: [ModelDescriptor] = []
    var fails = false

    func availableModels() async throws -> [ModelDescriptor] {
        if fails { throw URLError(.notConnectedToInternet) }
        return models
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { c in
            c.yield(.text("hi from \(source.rawValue)"))
            c.yield(.done(finishReason: "stop"))
            c.finish()
        }
    }
}

func descriptor(_ id: String, _ source: ModelSource) -> ModelDescriptor {
    ModelDescriptor(id: id, source: source, displayName: id, contextLength: nil,
                    capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
}

@MainActor
struct EngineRegistryTests {
    @Test func routesModelToEngineOfSameSource() async throws {
        let registry = EngineRegistry()
        registry.register(FakeEngine(source: .apple))
        registry.register(FakeEngine(source: .anyrouter))
        let engine = registry.engine(for: descriptor("anyrouter/x/y", .anyrouter))
        #expect(engine.source == .anyrouter)
    }

    @Test func allModelsKeepsRegistrationOrderAndSkipsFailingEngine() async {
        let registry = EngineRegistry()
        registry.register(FakeEngine(source: .apple, models: [descriptor("apple/foundation", .apple)]))
        registry.register(FakeEngine(source: .gguf, fails: true))
        registry.register(FakeEngine(source: .anyrouter, models: [descriptor("anyrouter/a/b", .anyrouter)]))
        let ids = await registry.allModels().map(\.id)
        #expect(ids == ["apple/foundation", "anyrouter/a/b"])
    }

    @Test func registeringSameSourceReplacesEngine() async {
        let registry = EngineRegistry()
        registry.register(FakeEngine(source: .mlx, models: [descriptor("mlx/old", .mlx)]))
        registry.register(FakeEngine(source: .mlx, models: [descriptor("mlx/new", .mlx)]))
        #expect(await registry.allModels().map(\.id) == ["mlx/new"])
    }

    @Test func missingEngineFailsStreamInsteadOfCrashing() async {
        let registry = EngineRegistry()
        let model = descriptor("gguf/r/f", .gguf)
        let stream = registry.engine(for: model).stream(model: model, messages: [], params: GenerationParams())
        await #expect(throws: EngineNotRegisteredError.self) {
            for try await _ in stream {}
        }
    }

    @Test func streamDeliversDeltasInOrder() async throws {
        let model = descriptor("apple/foundation", .apple)
        var out: [ChatDelta] = []
        for try await d in FakeEngine(source: .apple).stream(model: model, messages: [], params: GenerationParams()) {
            out.append(d)
        }
        #expect(out == [.text("hi from apple"), .done(finishReason: "stop")])
    }
}
