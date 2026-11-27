import Foundation

/// Demo and UI test runs never reach the network: this transport reports half of every file and then waits, so the Voice
/// Mode download screens can be tested in their downloading state.
@MainActor
final class DemoVoiceTransport: VoiceDownloadTransport {
    var onEvent: (@MainActor (DownloadCallback) -> Void)?

    func enqueue(modelID: String, file: VoiceModelFile) {
        let entry = DownloadTaskTag(voiceModelID: modelID, path: file.path).entryID
        onEvent?(.progress(entryID: entry, path: file.path, writtenBytes: file.sizeBytes / 2))
    }

    func cancel(modelID: String) async {}

    func livePaths(modelID: String) async -> Set<String> { [] }
}

extension DemoData {
    /// Voice settings and models of a demo run: a throwaway defaults suite and folder, so every launch starts with no speech
    /// model chosen or installed, and the transport above.
    @MainActor
    static func voiceHub() -> VoiceHub {
        let root = FileManager.default.temporaryDirectory.appending(path: "demo-voice-\(UUID().uuidString)", directoryHint: .isDirectory)
        let defaults = UserDefaults(suiteName: "demo.voice.\(UUID().uuidString)") ?? .standard
        return VoiceHub(
            settings: VoiceSettings(defaults: defaults),
            downloader: VoiceModelDownloader(storage: VoiceModelStorage(root: root), transport: DemoVoiceTransport()))
    }
}
