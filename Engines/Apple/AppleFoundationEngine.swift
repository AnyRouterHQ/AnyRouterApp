import Foundation
import FoundationModels

/// On-device Apple Foundation Models behind the `ChatEngine` contract.
struct AppleFoundationEngine: ChatEngine {
    static let modelID = "apple/foundation"

    enum Failure: LocalizedError {
        case unavailable(String)
        case emptyPrompt

        var errorDescription: String? {
            switch self {
            case .unavailable(let note): return note
            case .emptyPrompt: return "Send a message first."
            }
        }
    }

    var source: ModelSource { .apple }

    /// Human-readable availability. `nil` means the model is ready.
    static func unavailabilityNote() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This device cannot run Apple Foundation Models."
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in Settings to use the on-device model."
            case .modelNotReady: return "Apple Foundation Models is still downloading."
            @unknown default: return "Apple Foundation Models is unavailable."
            }
        @unknown default:
            return "Apple Foundation Models is unavailable."
        }
    }

    func availableModels() async throws -> [ModelDescriptor] {
        [
            ModelDescriptor(
                id: Self.modelID,
                source: .apple,
                displayName: "Apple Intelligence",
                contextLength: 4096,
                capabilities: ["chat"],
                sizeBytes: nil,
                isInstalled: Self.unavailabilityNote() == nil
            )
        ]
    }

    func stream(
        model: ModelDescriptor,
        messages: [ChatMessage],
        params: GenerationParams
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let note = Self.unavailabilityNote() { throw Failure.unavailable(note) }
                    let built: ApplePrompt.Built
                    do {
                        built = try ApplePrompt.build(messages: messages, params: params)
                    } catch {
                        throw Failure.emptyPrompt
                    }
                    let session = built.instructions.map { LanguageModelSession(instructions: $0) }
                        ?? LanguageModelSession()
                    let options = GenerationOptions(
                        sampling: .random(probabilityThreshold: params.topP),
                        temperature: params.temperature,
                        maximumResponseTokens: params.maxTokens
                    )
                    var tracker = SnapshotDeltaTracker()
                    for try await snapshot in session.streamResponse(to: built.prompt, options: options) {
                        try Task.checkCancellation()
                        if let delta = tracker.delta(for: snapshot.content) {
                            continuation.yield(.text(delta))
                        }
                    }
                    continuation.yield(.done(finishReason: "stop"))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
