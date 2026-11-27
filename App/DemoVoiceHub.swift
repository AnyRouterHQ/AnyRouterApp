import Foundation

/// Demo and UI test runs never reach the network: this fetcher reports part of a model and then waits, so the Voice Mode
/// download screens can be tested in their downloading state.
struct DemoVoiceFetcher: VoiceFileFetching {
    func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        progress(40_000_000)
        try await Task.sleep(for: .seconds(3600))
    }
}

extension DemoData {
    /// Voice settings and models of a demo run: a throwaway defaults suite and folder, so every launch starts with no speech
    /// model chosen or installed, and the fetcher above.
    @MainActor
    static func voiceHub() -> VoiceHub {
        let root = FileManager.default.temporaryDirectory.appending(path: "demo-voice-\(UUID().uuidString)", directoryHint: .isDirectory)
        let defaults = UserDefaults(suiteName: "demo.voice.\(UUID().uuidString)") ?? .standard
        return VoiceHub(
            settings: VoiceSettings(defaults: defaults),
            downloader: VoiceModelDownloader(storage: VoiceModelStorage(root: root), fetcher: DemoVoiceFetcher()))
    }
}
