import Foundation
import Observation

/// Voice preferences, backed by `UserDefaults`. A nil model id means the System engine.
@MainActor @Observable
final class VoiceSettings {
    private enum Key {
        static let stt = "voice.stt"
        static let tts = "voice.tts"
        static let readAloud = "voice.readRepliesAloud"
        static let forced = "voice.dictationLanguage"
        static let last = "voice.lastLanguage"
        static let modeDeclined = "voice.modeDeclined"
        static let modeTarget = "voice.modeTarget"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedSTT: String? {
        get { access(keyPath: \.selectedSTT); return defaults.string(forKey: Key.stt) }
        set { withMutation(keyPath: \.selectedSTT) { defaults.set(newValue, forKey: Key.stt) } }
    }

    var selectedTTS: String? {
        get { access(keyPath: \.selectedTTS); return defaults.string(forKey: Key.tts) }
        set { withMutation(keyPath: \.selectedTTS) { defaults.set(newValue, forKey: Key.tts) } }
    }

    /// Speak every reply as it arrives. Off by default; the speaker button under a reply works either way.
    var readRepliesAloud: Bool {
        get { access(keyPath: \.readRepliesAloud); return defaults.bool(forKey: Key.readAloud) }
        set { withMutation(keyPath: \.readRepliesAloud) { defaults.set(newValue, forKey: Key.readAloud) } }
    }

    /// The language picked on the badge in the composer. Nil means detect it.
    var forcedLanguage: VoiceLanguage? {
        get { access(keyPath: \.forcedLanguage); return defaults.string(forKey: Key.forced).map(VoiceLanguage.init) }
        set { withMutation(keyPath: \.forcedLanguage) { defaults.set(newValue?.code, forKey: Key.forced) } }
    }

    /// "Not Now" on the Voice Mode download. The voice button then dictates with the System engine; Settings › Voice
    /// still offers the download.
    var voiceModeDeclined: Bool {
        get { access(keyPath: \.voiceModeDeclined); return defaults.bool(forKey: Key.modeDeclined) }
        set { withMutation(keyPath: \.voiceModeDeclined) { defaults.set(newValue, forKey: Key.modeDeclined) } }
    }

    /// The speech model chosen on the Voice Mode download, from Download until it is installed (then it becomes
    /// `selectedSTT`) or cancelled. It survives a relaunch, so a download that finished while the app was away is still
    /// the model Voice Mode uses.
    var voiceModeTarget: String? {
        get { access(keyPath: \.voiceModeTarget); return defaults.string(forKey: Key.modeTarget) }
        set { withMutation(keyPath: \.voiceModeTarget) { defaults.set(newValue, forKey: Key.modeTarget) } }
    }

    /// The language dictation settled on last time, tried first next time.
    var lastLanguage: VoiceLanguage? {
        get { access(keyPath: \.lastLanguage); return defaults.string(forKey: Key.last).map(VoiceLanguage.init) }
        set { withMutation(keyPath: \.lastLanguage) { defaults.set(newValue?.code, forKey: Key.last) } }
    }
}
