import AVFoundation
import Speech

/// Microphone and speech recognition, asked at first use only. The pre-prompt sheet comes first (`DictationRules.needsExplanation`).
@MainActor
enum VoicePermissions {
    enum Status: Equatable, Sendable {
        case notDetermined, granted, denied
    }

    static var microphone: Status {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: .notDetermined
        case .granted: .granted
        default: .denied
        }
    }

    static var speechRecognition: Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        default: .denied
        }
    }

    /// Asks for whatever is still undecided, microphone first. Throws the error to show when either is denied.
    static func request() async throws {
        if microphone == .notDetermined { _ = await AVAudioApplication.requestRecordPermission() }
        guard microphone == .granted else { throw VoiceError.microphoneDenied }
        if speechRecognition == .notDetermined {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        }
        guard speechRecognition == .granted else { throw VoiceError.speechRecognitionDenied }
    }
}
