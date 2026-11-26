import Foundation
import Observation

/// What the engines asked so far have answered. Each engine's own list is kept apart, so a caller can lay a
/// new answer over an earlier one without losing the models of an engine that has not answered yet.
struct ModelListing: Sendable {
    /// Every engine that was asked, in registration order.
    var order: [ModelSource]
    /// The lists of the engines that answered without an error.
    var lists: [ModelSource: [ModelDescriptor]] = [:]
    /// The engines that threw or did not answer in time, with a short reason a person can read.
    var failures: [ModelSource: String] = [:]

    /// Everything the answering engines listed, in registration order.
    var models: [ModelDescriptor] { order.flatMap { lists[$0] ?? [] } }
}

/// An engine that did not answer within the registry's limit.
struct ListingTimedOut: LocalizedError {
    var errorDescription: String? { "The model list did not load in time." }
}

/// One registry the UI talks to. It never branches on source.
@MainActor @Observable
final class EngineRegistry {
    private var engines: [any ChatEngine] = []
    /// How long one engine may take to list its models. A cloud list that hangs must not hold the picker forever.
    private let listTimeout: Duration

    init(listTimeout: Duration = .seconds(20)) {
        self.listTimeout = listTimeout
    }

    func register(_ engine: any ChatEngine) {
        engines.removeAll { $0.source == engine.source }
        engines.append(engine)
    }

    private struct Answer: Sendable {
        let index: Int
        let result: Result<[ModelDescriptor], any Error>
    }

    /// The model list as it grows: one value each time an engine answers, always every answer so far. Engines are
    /// asked at the same time, so a slow cloud listing never holds back the on-device models. An engine that throws
    /// or runs past the limit is recorded in `failures`, not hidden. The stream ends when every engine has answered.
    func modelListings() -> AsyncStream<ModelListing> {
        let snapshot = engines
        let limit = listTimeout
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Answer.self) { group in
                    for (index, engine) in snapshot.enumerated() {
                        group.addTask {
                            do { return Answer(index: index, result: .success(try await engine.availableModels())) } catch {
                                return Answer(index: index, result: .failure(error))
                            }
                        }
                        group.addTask {
                            try? await Task.sleep(for: limit)
                            return Answer(index: index, result: .failure(ListingTimedOut()))
                        }
                    }
                    var listing = ModelListing(order: snapshot.map(\.source))
                    var settled: Set<Int> = []
                    for await answer in group {
                        // The first answer for an engine counts; its timer or a late reply is ignored.
                        guard settled.insert(answer.index).inserted else { continue }
                        let source = snapshot[answer.index].source
                        switch answer.result {
                        case .success(let models): listing.lists[source] = models
                        case .failure(let error): listing.failures[source] = error.localizedDescription
                        }
                        continuation.yield(listing)
                        if settled.count == snapshot.count {
                            // Finish now: an engine that ignores cancellation must not keep the caller waiting.
                            continuation.finish()
                            group.cancelAll()
                            break
                        }
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
        for await listing in modelListings() { latest = listing.models }
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
