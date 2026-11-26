import AVFoundation

/// The one audio session the app shares between dictation and spoken replies.
@MainActor
enum VoiceAudioSession {
    static func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }

    static func activateRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true)
    }

    /// Lets other apps' audio come back. Best effort: a session that is still in use refuses.
    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
