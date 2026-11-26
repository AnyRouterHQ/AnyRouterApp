import AVFoundation

/// Spoken replies with the system's own voices (`AVSpeechSynthesizer`). Always available; picks the best installed
/// voice per language, so a downloaded Enhanced or Premium voice is used without any setting.
@MainActor
final class SystemTextToSpeech: NSObject, TextToSpeech, AVSpeechSynthesizerDelegate {
    let id = VoiceModel.systemID
    private let synthesizer = AVSpeechSynthesizer()
    private var playing: CheckedContinuation<Void, Never>?
    private var current: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func supports(_ language: VoiceLanguage) async -> Bool { Self.voice(for: language) != nil }

    func speak(_ text: String, language: VoiceLanguage) async throws {
        guard let voice = Self.voice(for: language) else { throw VoiceError.languageUnavailable(language) }
        stop()
        try VoiceAudioSession.activatePlayback()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        current = ObjectIdentifier(utterance)
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                playing = continuation
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    func stop() {
        current = nil
        playing?.resume()
        playing = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finished = ObjectIdentifier(utterance)
        Task { @MainActor in self.complete(finished) }
    }

    private func complete(_ utterance: ObjectIdentifier) {
        guard utterance == current else { return }
        current = nil
        playing?.resume()
        playing = nil
    }

    // MARK: Voices

    /// The best installed voice for a language: highest quality, then the device's region. Novelty voices are skipped.
    static func voice(for language: VoiceLanguage) -> AVSpeechSynthesisVoice? {
        let region = Locale.current.region?.identifier
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { VoiceLanguage($0.language) == language && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .max { score($0, region: region) < score($1, region: region) }
    }

    private static func score(_ voice: AVSpeechSynthesisVoice, region: String?) -> Int {
        let regionMatch = region.map { voice.language.hasSuffix("-" + $0) } ?? false
        return voice.quality.rawValue * 10 + (regionMatch ? 1 : 0)
    }

    /// True when the best voice for the language is the basic one, so Settings can point to the better downloads.
    static func hasOnlyBasicVoice(for language: VoiceLanguage) -> Bool {
        guard let voice = voice(for: language) else { return false }
        return voice.quality == .default
    }
}
