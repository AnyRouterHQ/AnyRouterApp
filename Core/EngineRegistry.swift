import Foundation
import Observation

/// One registry the UI talks to. It never branches on source.
@MainActor @Observable
final class EngineRegistry {
    private var engines: [any ChatEngine] = []

    func register(_ engine: any ChatEngine) {
        engines.removeAll { $0.source == engine.source }
        engines.append(engine)
    }

    /// Models from every engine, in registration order. An engine that throws is skipped.
    func allModels() async -> [ModelDescriptor] {
        var result: [ModelDescriptor] = []
        for engine in engines {
            if let models = try? await engine.availableModels() {
                result.append(contentsOf: models)
            }
        }
        return result
    }

    /// Returns the engine for the model's source. With none registered, the returned engine fails its stream.
    func engine(for model: ModelDescriptor) -> any ChatEngine {
        engines.first { $0.source == model.source } ?? MissingEngine(source: model.source)
    }
}

struct EngineNotRegisteredError: Error, LocalizedError {
    let source: ModelSource
    var errorDescription: String? { "No engine registered for \(source.rawValue)." }
}

private struct MissingEngine: ChatEngine {
    let source: ModelSource

    func availableModels() async throws -> [ModelDescriptor] { [] }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { $0.finish(throwing: EngineNotRegisteredError(source: source)) }
    }
}
