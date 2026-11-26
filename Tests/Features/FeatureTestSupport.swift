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

/// Thread-safe list of the model ids an engine was asked to stream with.
final class ModelLog: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [String] = []
    var values: [String] { lock.withLock { raw } }
    func add(_ id: String) { lock.withLock { raw.append(id) } }
}

struct TestFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Records the `tools` argument of each stream call: nil, or the tool names.
final class ToolsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [[String]?] = []
    var seen: [[String]?] { lock.withLock { raw } }
    func record(_ tools: (any ToolHost)?) { lock.withLock { raw.append(tools?.specs.map(\.name)) } }
}

/// The text of the last message of every request an engine got.
final class MessagesRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [String] = []
    var lastTexts: [String] { lock.withLock { raw } }
    func record(_ messages: [ChatMessage]) { lock.withLock { raw.append(messages.last?.content ?? "") } }
}

/// Tool host with fixed specs; never asked to run anything in these tests.
struct StubToolHost: ToolHost {
    var specs: [ToolSpec] = [ToolSpec(name: "search", title: nil, description: "", inputSchemaJSON: "{}", isReadOnly: true)]
    func execute(_ call: ToolCall) async -> ToolResult {
        ToolResult(callID: call.id, name: call.name, text: "", isError: false)
    }
}

func testModelWithTools() -> ModelDescriptor {
    ModelDescriptor(id: "apple/foundation", source: .apple, displayName: "tools", contextLength: nil,
                    capabilities: ["chat", "tools"], sizeBytes: nil, isInstalled: true)
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
    /// Model id of every call, in order.
    var usedModels = ModelLog()
    /// When set, every call replies "reply N".
    var numberedReplies = false
    /// Played after the text chunks, for example tool calls and results.
    var deltas: [ChatDelta] = []
    var toolsSeen = ToolsRecorder()
    var messagesSeen = MessagesRecorder()

    func availableModels() async throws -> [ModelDescriptor] { models }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        stream(model: model, messages: messages, params: params, tools: nil)
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, tools: (any ToolHost)?)
        -> AsyncThrowingStream<ChatDelta, Error> {
        toolsSeen.record(tools)
        messagesSeen.record(messages)
        let n = calls.next()
        let deltas = self.deltas
        usedModels.add(model.id)
        let chunks = numberedReplies ? ["reply \(n)"] : self.chunks
        let failure = self.failure
        let hangs = self.hangs
        let terminated = self.terminated
        return AsyncThrowingStream { continuation in
            let producer = Task {
                for chunk in chunks { continuation.yield(.text(chunk)) }
                for delta in deltas { continuation.yield(delta) }
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
