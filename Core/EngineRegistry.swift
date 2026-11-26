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

    /// The model list as it grows: one value each time an engine answers, always the whole list so far in
    /// registration order. Engines are asked at the same time, so a slow cloud listing never holds back the
    /// on-device models. An engine that throws is skipped. The stream ends when every engine has answered.
    func modelListings() -> AsyncStream<[ModelDescriptor]> {
        let snapshot = engines
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: (Int, [ModelDescriptor]).self) { group in
                    for (index, engine) in snapshot.enumerated() {
                        group.addTask { (index, (try? await engine.availableModels()) ?? []) }
                    }
                    var answered: [Int: [ModelDescriptor]] = [:]
                    for await (index, models) in group {
                        answered[index] = models
                        continuation.yield(answered.sorted { $0.key < $1.key }.flatMap(\.value))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The finished list: every engine has answered.
    func allModels() async -> [ModelDescriptor] {
        var latest: [ModelDescriptor] = []
        for await listing in modelListings() { latest = listing }
        return latest
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
