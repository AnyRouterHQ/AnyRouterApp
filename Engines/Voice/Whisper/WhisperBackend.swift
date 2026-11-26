import Foundation

/// The part of Whisper the engine needs: a microphone that collects audio, and passes of the model over it. The
/// WhisperKit-backed one is the only file that imports WhisperKit; tests use a fake. Not Sendable on purpose: a backend
/// lives inside one task (the runner), is built there and never shared.
protocol WhisperBackend {
    /// Starts the microphone. Audio and levels collect until `stopRecording`.
    func startRecording() throws
    /// Samples collected so far, at 16 kHz.
    var sampleCount: Int { get }
    /// One loudness value per short buffer collected so far, 0 to 1, relative to the quietest recent buffer.
    var energy: [Float] { get }
    func samples() -> [Float]
    /// Safe to call more than once.
    func stopRecording()
    /// Whisper's code for the language spoken in `samples`.
    func detectLanguage(in samples: [Float]) async throws -> String
    /// The phrases in `samples` after `seconds`, spoken in `language` (a Whisper code).
    func transcribe(_ samples: [Float], language: String, from seconds: Float) async throws -> [WhisperSegment]
    /// Frees the model's memory.
    func unload() async
}

/// Builds a backend: loads the model, which takes seconds. Runs off the main actor.
typealias WhisperBackendLoader = @Sendable () async throws -> sending any WhisperBackend

/// The audio session around a dictation, on the main actor where `AVAudioSession` belongs.
struct WhisperAudioHooks: Sendable {
    var activate: @MainActor @Sendable () throws -> Void
    var deactivate: @MainActor @Sendable () -> Void

    static let silent = WhisperAudioHooks(activate: {}, deactivate: {})
}
