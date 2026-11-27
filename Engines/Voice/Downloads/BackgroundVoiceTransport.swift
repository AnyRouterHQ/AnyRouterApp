import Foundation

/// Voice model files as tasks of the one background session that `ModelDownloadManager` owns. There is no second session:
/// the system relaunches the app for this session's events, and `AppDelegate` holds the one completion handler.
@MainActor
final class BackgroundVoiceTransport: VoiceDownloadTransport {
    var onEvent: (@MainActor (DownloadCallback) -> Void)?
    private let manager: ModelDownloadManager

    init(manager: ModelDownloadManager) {
        self.manager = manager
        manager.voiceHandler = { [weak self] in self?.onEvent?($0) }
    }

    func enqueue(modelID: String, file: VoiceModelFile) { manager.startVoiceTask(modelID: modelID, file: file) }

    func cancel(modelID: String) async { await manager.cancelVoiceTasks(modelID: modelID) }

    func livePaths(modelID: String) async -> Set<String> { await manager.liveVoicePaths(modelID: modelID) }
}
