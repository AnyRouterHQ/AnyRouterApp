import Foundation

/// Spoken replies, one sentence at a time. The System engine is always there; a downloaded model is another conformance.
@MainActor
protocol TextToSpeech: AnyObject {
    var id: String { get }
    /// Whether this engine has a voice for the language on this device now.
    func supports(_ language: VoiceLanguage) async -> Bool
    /// Speaks the text and returns when it has been played. Throws `VoiceError.languageUnavailable` when there is no voice.
    func speak(_ text: String, language: VoiceLanguage) async throws
    /// Stops what is playing now. A `speak` in flight returns.
    func stop()
}
