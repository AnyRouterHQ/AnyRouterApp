import Foundation
import FoundationModels

/// Apple Foundation Models behind the `ChatEngine` contract: the on-device model, and from iOS 27 the same framework's
/// Private Cloud Compute model (`ApplePCCLogic.modelID`), which is a second model of this engine, not an engine of its own.
struct AppleFoundationEngine: ChatEngine {
    static let modelID = "apple/foundation"

    /// Reads Private Cloud Compute. Tests pass a stub.
    var pcc: any ApplePCCProbing = ApplePCCReader()

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

    /// Tool calling needs the model itself, so it is advertised only while the model is ready.
    static func capabilities(available: Bool) -> Set<String> {
        available ? ["chat", "tools"] : ["chat"]
    }

    func availableModels() async throws -> [ModelDescriptor] {
        let ready = Self.unavailabilityNote() == nil
        let cloud = ApplePCCLogic.descriptor(await pcc.status())
        return [
            ModelDescriptor(
                id: Self.modelID,
                source: .apple,
                displayName: "Apple Intelligence",
                contextLength: 4096,
                capabilities: Self.capabilities(available: ready),
                sizeBytes: nil,
                isInstalled: ready,
                // The reason shows in the picker when Apple Intelligence cannot be used.
                summary: Self.unavailabilityNote()
            ),
            cloud,
        ]
    }

    func stream(
        model: ModelDescriptor,
        messages: [ChatMessage],
        params: GenerationParams
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        stream(model: model, messages: messages, params: params, tools: nil)
    }

    func stream(
        model: ModelDescriptor,
        messages: [ChatMessage],
        params: GenerationParams,
        tools: (any ToolHost)?
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let scope = ToolRunScope()
            let pcc = pcc
            let task = Task {
                do {
                    let onCloud = model.id == ApplePCCLogic.modelID
                    if onCloud {
                        if let reason = ApplePCCLogic.reason(await pcc.status()) { throw Failure.unavailable(reason) }
                    } else if let note = Self.unavailabilityNote() {
                        throw Failure.unavailable(note)
                    }
                    let built: ApplePrompt.Built
                    do {
                        built = try ApplePrompt.build(messages: messages, params: params)
                    } catch {
                        throw Failure.emptyPrompt
                    }
                    var offered: [any Tool] = []
                    if let host = tools {
                        offered = AppleDynamicTool.make(
                            specs: host.specs, host: host, scope: scope,
                            emit: { delta in _ = continuation.yield(delta) })
                    }
                    let instructions = AppleToolGuidance.instructions(base: built.instructions, offeringTools: !offered.isEmpty)
                    let session: LanguageModelSession
                    if onCloud {
                        session = try Self.cloudSession(tools: offered, instructions: instructions)
                    } else {
                        session = instructions.map { LanguageModelSession(tools: offered, instructions: $0) }
                            ?? LanguageModelSession(tools: offered)
                    }
                    let options = GenerationOptions(
                        sampling: .random(probabilityThreshold: params.topP),
                        temperature: params.temperature,
                        maximumResponseTokens: params.maxTokens
                    )
                    var tracker = SnapshotDeltaTracker()
                    var seenCalls = 0
                    for try await snapshot in session.streamResponse(to: built.prompt, options: options) {
                        try Task.checkCancellation()
                        let finished = scope.finishedCalls
                        if finished != seenCalls {
                            seenCalls = finished
                            tracker.markToolBoundary()
                        }
                        if let delta = tracker.delta(for: snapshot.content) {
                            continuation.yield(.text(delta))
                        }
                    }
                    continuation.yield(.done(finishReason: "stop"))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.userFacing(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                scope.cancelAll()
            }
        }
    }

    /// A session on Private Cloud Compute. Only an iOS 27 SDK build can make one; any other build never gets here,
    /// because the model reports `.needsNewerSystem` and the request stops at the availability check.
    private static func cloudSession(tools: [any Tool], instructions: String?) throws -> LanguageModelSession {
        #if APPLE_PCC_SDK
        if #available(iOS 27.0, *) { return ApplePCCReader.session(tools: tools, instructions: instructions) }
        #endif
        throw Failure.unavailable(ApplePCCLogic.reason(.needsNewerSystem) ?? "")
    }

    /// Private Cloud Compute's own errors (daily limit, no network, busy) in words; every other error as it is.
    private static func userFacing(_ error: any Error) -> any Error {
        #if APPLE_PCC_SDK
        if #available(iOS 27.0, *), let failure = ApplePCCReader.failure(error) {
            return Failure.unavailable(ApplePCCLogic.text(failure))
        }
        #endif
        return error
    }
}
