import Foundation
import WhisperKit

/// Whisper on Core ML through WhisperKit, loaded from the folder the voice downloader filled. The only file that
/// imports WhisperKit. WhisperKit is not Sendable, so it is created here, kept in this object, and the object is
/// handed to the runner task that uses it (see `WhisperBackendLoader`).
final class WhisperKitBackend: WhisperBackend {
    private let kit: WhisperKit
    private var isRecording = false

    private init(kit: WhisperKit) { self.kit = kit }

    /// Loads the three Core ML models and the tokenizer from `folder`. Nothing is downloaded: the tokenizer files sit at
    /// the folder's root and WhisperKit finds them through `tokenizerFolder`, and `download` is off.
    /// `prewarm` loads one model at a time first, which lowers the peak memory of a large model's first load.
    static func load(folder: URL, prewarm: Bool) async throws -> sending any WhisperBackend {
        let config = WhisperKitConfig(
            modelFolder: folder.path, tokenizerFolder: folder, verbose: false, logLevel: .error,
            prewarm: prewarm, load: true, download: false)
        do {
            let kit = try await WhisperKit(config)
            return WhisperKitBackend(kit: kit)
        } catch {
            throw translated(error)
        }
    }

    func startRecording() throws {
        do {
            try kit.audioProcessor.startRecordingLive(inputDeviceID: nil, callback: nil)
            isRecording = true
        } catch {
            throw Self.translated(error)
        }
    }

    var sampleCount: Int { kit.audioProcessor.audioSamples.count }
    var energy: [Float] { kit.audioProcessor.relativeEnergy }
    func samples() -> [Float] { Array(kit.audioProcessor.audioSamples) }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        kit.audioProcessor.stopRecording()
    }

    func detectLanguage(in samples: [Float]) async throws -> String {
        do {
            return try await kit.detectLangauge(audioArray: samples).language
        } catch {
            throw Self.translated(error)
        }
    }

    func transcribe(_ samples: [Float], language: String, from seconds: Float) async throws -> [WhisperSegment] {
        var options = DecodingOptions()
        options.language = language
        options.detectLanguage = false
        options.usePrefillPrompt = true
        options.skipSpecialTokens = true
        options.wordTimestamps = false
        options.clipTimestamps = [seconds]
        do {
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
            return results.flatMap { $0.segments }.map { WhisperSegment(start: $0.start, end: $0.end, text: $0.text) }
        } catch {
            throw Self.translated(error)
        }
    }

    func unload() async {
        stopRecording()
        await kit.unloadModels()
    }

    private static func translated(_ error: any Error) -> WhisperFailure {
        if let failure = error as? WhisperFailure { return failure }
        guard let error = error as? WhisperError else { return .failed(error.localizedDescription) }
        switch error {
        case .modelsUnavailable, .tokenizerUnavailable, .initializationError: return .modelUnavailable
        case .microphoneUnavailable: return .microphoneUnavailable
        default: return .failed(error.localizedDescription)
        }
    }
}

extension WhisperKitSpeechToText {
    /// The engine for an installed Whisper model: `folder` is where the downloader put it. Loads nothing yet.
    static func installed(model: VoiceModel, folder: URL) -> WhisperKitSpeechToText {
        // A large model's first load is the one that can run a phone short of memory.
        let prewarm = model.sizeBytes > 400_000_000
        return WhisperKitSpeechToText(
            model: model, loader: { try await WhisperKitBackend.load(folder: folder, prewarm: prewarm) }, audio: .system)
    }
}

extension WhisperAudioHooks {
    /// The app's shared recording session.
    static let system = WhisperAudioHooks(
        activate: { try VoiceAudioSession.activateRecording() }, deactivate: { VoiceAudioSession.deactivate() })
}
