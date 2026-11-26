import Foundation
import SwiftData
@testable import AnyRouter

/// Thread-safe flag the scripted engine flips when its stream is torn down.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raw = false
    var value: Bool {
        get { lock.withLock { raw } }
        set { lock.withLock { raw = newValue } }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var raw = 0
    func next() -> Int { lock.withLock { raw += 1; return raw } }
}

struct TestFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Engine that plays a script. `hangs` keeps the stream open after the chunks until it is cancelled.
struct ScriptedEngine: ChatEngine {
    var source: ModelSource = .apple
    var models: [ModelDescriptor] = [testModel()]
    var chunks: [String] = []
    var failure: String?
    var hangs = false
    var terminated = Flag()
    var calls = Counter()
    /// When set, every call replies "reply N".
    var numberedReplies = false

    func availableModels() async throws -> [ModelDescriptor] { models }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        let n = calls.next()
        let chunks = numberedReplies ? ["reply \(n)"] : self.chunks
        let failure = self.failure
        let hangs = self.hangs
        let terminated = self.terminated
        return AsyncThrowingStream { continuation in
            let producer = Task {
                for chunk in chunks { continuation.yield(.text(chunk)) }
                if let failure {
                    continuation.finish(throwing: TestFailure(message: failure))
                } else if !hangs {
                    continuation.yield(.done(finishReason: "stop"))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                terminated.value = true
                producer.cancel()
            }
        }
    }
}

func testModel(id: String = "apple/foundation", source: ModelSource = .apple, installed: Bool = true) -> ModelDescriptor {
    ModelDescriptor(id: id, source: source, displayName: id, contextLength: nil,
                    capabilities: ["chat"], sizeBytes: nil, isInstalled: installed)
}

func testDefaults() -> UserDefaults {
    UserDefaults(suiteName: "anyrouter.tests.\(UUID().uuidString)")!
}

/// Polls the main actor until `condition` holds or the attempts run out.
@MainActor
func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<500 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
