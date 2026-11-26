import Foundation

/// The part of the neural voice the engine needs: say a sentence out loud. The TTSKit-backed one is the only file that
/// imports TTSKit; tests use a fake. TTSKit declares itself Sendable and the engine plays one sentence at a time, so a
/// backend is shared between the engine's tasks.
protocol TTSBackend: Sendable {
    /// Speaks `text` and returns when it has been played. Cancelling the calling task stops the sound and throws.
    func speak(_ text: String, language: TTSKitLanguage) async throws
    /// Frees the model's memory.
    func unload() async
}

/// Builds a backend: loads the model, which takes seconds. Runs off the main actor.
typealias TTSBackendLoader = @Sendable () async throws -> any TTSBackend
