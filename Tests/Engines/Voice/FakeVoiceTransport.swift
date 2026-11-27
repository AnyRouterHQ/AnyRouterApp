import Foundation
@testable import AnyRouter

/// Plays the background session: a queued file is served from a dictionary into the model's partial folder, then reported
/// as finished, a moment later (a task hop), like the delegate does. `hangs` queues files that never arrive.
@MainActor
final class FakeVoiceTransport: VoiceDownloadTransport {
    var onEvent: (@MainActor (DownloadCallback) -> Void)?
    var fails = false
    var hangs = false
    /// Paths the "system" still has running, as after a relaunch.
    var live: Set<String> = []
    private(set) var enqueued: [String] = []
    private(set) var cancelled: [String] = []
    private var bytes: [URL: Data]
    private let storage: VoiceModelStorage

    init(storage: VoiceModelStorage, _ bytes: [URL: Data] = [:]) {
        self.storage = storage
        self.bytes = bytes
    }

    func serve(_ url: URL, _ data: Data) { bytes[url] = data }

    func enqueue(modelID: String, file: VoiceModelFile) {
        enqueued.append(file.path)
        guard !hangs else { return }
        Task { @MainActor in deliver(modelID, file) }
    }

    func cancel(modelID: String) async { cancelled.append(modelID) }

    func livePaths(modelID: String) async -> Set<String> { live }

    /// What the delegate does when a file is complete: put it in the partial folder, then say so.
    func land(_ modelID: String, path: String, _ data: Data) throws {
        let url = storage.partialFileURL(id: modelID, path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func send(_ callback: DownloadCallback) { onEvent?(callback) }

    private func deliver(_ modelID: String, _ file: VoiceModelFile) {
        let entry = DownloadTaskTag(voiceModelID: modelID, path: file.path).entryID
        if fails {
            send(.fileFailed(entryID: entry, path: file.path, message: "The Internet connection appears to be offline."))
            return
        }
        guard let data = bytes[file.url], (try? land(modelID, path: file.path, data)) != nil else { return }
        send(.progress(entryID: entry, path: file.path, writtenBytes: Int64(data.count) / 2))
        send(.fileFinished(entryID: entry, path: file.path))
    }
}
