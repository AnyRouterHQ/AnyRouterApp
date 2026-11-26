import Foundation
import TTSKit

/// Qwen3-TTS 0.6B on Core ML through TTSKit, loaded from the folder the voice downloader filled. The only file that
/// imports TTSKit. TTSKit is Sendable (it says so itself) and the engine plays one sentence at a time, so this object is
/// shared by the engine's tasks.
final class TTSKitBackend: TTSBackend {
    private let kit: TTSKit

    private init(kit: TTSKit) { self.kit = kit }

    /// Loads the six Core ML models and the tokenizer from `folder`. Nothing is downloaded: `download` is off, the model
    /// folder holds `qwen3_tts/<component>/<versionDir>/<variant>/`, and the tokenizer files sit at its root, where
    /// `tokenizerFolder` points (TTSKit would otherwise fetch them from Hugging Face). The engine has already set the
    /// audio session, so TTSKit only activates it.
    static func load(folder: URL) async throws -> any TTSBackend {
        let config = TTSKitConfig(
            model: .qwen3TTS_0_6b, modelFolder: folder, tokenizerFolder: folder, verbose: false,
            download: false, load: true, preserveExistingAudioSession: true)
        do {
            let kit = try await TTSKit(config)
            return TTSKitBackend(kit: kit)
        } catch {
            throw translated(error)
        }
    }

    func speak(_ text: String, language: TTSKitLanguage) async throws {
        do {
            _ = try await kit.play(text: text, voice: language.speaker, language: language.rawValue)
        } catch {
            // A cancelled or failed play leaves its audio engine running; shut it without waiting for the queue.
            await kit.audioOutput.stopPlayback(waitForCompletion: false)
            if let known = error as? TTSError, known == .emptyText { return }
            throw Self.translated(error)
        }
    }

    func unload() async {
        await kit.audioOutput.stopPlayback(waitForCompletion: false)
        await kit.unloadModels()
    }

    private static func translated(_ error: any Error) -> any Error {
        if error is CancellationError { return error }
        guard let error = error as? TTSError else { return TTSFailure.failed(error.localizedDescription) }
        switch error {
        case .modelNotFound, .modelLoadingFailed, .invalidConfiguration, .tokenizerUnavailable: return TTSFailure.modelUnavailable
        case .audioOutputFailed(let detail): return TTSFailure.audioFailed(detail)
        case .emptyText, .generationFailed: return TTSFailure.failed(error.localizedDescription)
        }
    }
}

extension TTSKitTextToSpeech {
    /// The engine for an installed Qwen3-TTS model: `folder` is where the downloader put it. Loads nothing yet.
    static func installed(model: VoiceModel, folder: URL) -> TTSKitTextToSpeech {
        TTSKitTextToSpeech(model: model, loader: { try await TTSKitBackend.load(folder: folder) })
    }
}
