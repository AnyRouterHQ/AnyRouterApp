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
    /// Engines are asked at the same time, so a slow cloud listing does not hold back the on-device models.
    func allModels() async -> [ModelDescriptor] {
        let snapshot = engines
        let listings = await withTaskGroup(of: (Int, [ModelDescriptor]).self) { group in
            for (index, engine) in snapshot.enumerated() {
                group.addTask { (index, (try? await engine.availableModels()) ?? []) }
            }
            var collected: [(Int, [ModelDescriptor])] = []
            for await listing in group { collected.append(listing) }
            return collected
        }
        return listings.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
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
