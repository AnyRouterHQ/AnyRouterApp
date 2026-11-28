import CryptoKit
import Foundation
import Observation

/// How a download ended, for whoever started it.
enum VoiceDownloadOutcome: Equatable, Sendable {
    case installed
    case cancelled
    case failed
}

/// Where the bytes of a voice model come from. Production queues one task per file on the app's background session, which
/// keeps running while the app is suspended and relaunches it to finish (`BackgroundVoiceTransport`). A file that is
/// complete lands in `VoiceModelStorage.partialFileURL` before its `fileFinished` event, so the disk says what is done
/// even for events that arrived while no one was listening. Events carry `DownloadTaskTag` entry ids of voice models.
@MainActor
protocol VoiceDownloadTransport: AnyObject {
    var onEvent: (@MainActor (DownloadCallback) -> Void)? { get set }
    /// Queues the file. Several files of one model run at the same time.
    func enqueue(modelID: String, file: VoiceModelFile)
    /// Stops every queued or running file of the model.
    func cancel(modelID: String) async
    /// The paths of the model's files that are queued or running right now (after a relaunch: the ones the system kept).
    func livePaths(modelID: String) async -> Set<String>
}

/// Starts nothing. For tests and previews that never download; the app passes `BackgroundVoiceTransport`.
@MainActor
final class InertVoiceTransport: VoiceDownloadTransport {
    var onEvent: (@MainActor (DownloadCallback) -> Void)?
    func enqueue(modelID: String, file: VoiceModelFile) {}
    func cancel(modelID: String) async {}
    func livePaths(modelID: String) async -> Set<String> { [] }
}

/// Downloads voice models. The same `ModelDownloadState` machine as the chat models. A voice model is a folder of small
/// and medium files (up to about 650 MB) from Hugging Face. Every file of a model is queued at once on the transport, so the
/// system carries on while the app is suspended; this class checks each file when it lands (size, and sha256 where the
/// catalog pins one) and, when all are verified, moves them into place and writes the manifest last. A `.downloading`
/// marker in the model's folder lets `restore` pick the job up after a relaunch. A file that passed its checks is kept,
/// so Get after a failure continues where it stopped.
@MainActor @Observable
final class VoiceModelDownloader {
    private(set) var states: [String: ModelDownloadState] = [:]

    let storage: VoiceModelStorage
    @ObservationIgnored private let transport: any VoiceDownloadTransport
    @ObservationIgnored private var jobs: [String: Job] = [:]
    /// Resumes the task `start` returned when the download ends.
    @ObservationIgnored private var ends: [String: CheckedContinuation<Void, Never>] = [:]
    /// Called on the main actor when a download ends, whoever started it.
    @ObservationIgnored var onFinished: (@MainActor (String, VoiceDownloadOutcome) -> Void)?

    /// One download in flight: which files have bytes, have all their bytes, and have passed their checks.
    private struct Job {
        let model: VoiceModel
        var received: [String: Int64] = [:]
        var arrived: Set<String> = []
        var checking: Set<String> = []
        var verified: Set<String> = []

        var receivedBytes: Int64 {
            model.files.reduce(0) { sum, file in
                sum + (arrived.contains(file.path) ? file.sizeBytes : min(received[file.path] ?? 0, file.sizeBytes))
            }
        }
    }

    init(storage: VoiceModelStorage = VoiceModelStorage(), transport: any VoiceDownloadTransport = InertVoiceTransport()) {
        self.storage = storage
        self.transport = transport
        transport.onEvent = { [weak self] in self?.handle($0) }
    }

    func state(for model: VoiceModel) -> ModelDownloadState {
        if model.isSystem { return .installed }
        return states[model.id] ?? (storage.isInstalled(model.id) ? .installed : .notInstalled)
    }

    func isInstalled(_ model: VoiceModel) -> Bool { state(for: model) == .installed }

    /// Ids with a download in flight.
    var activeIDs: Set<String> { Set(states.filter { $0.value.isActive }.map(\.key)) }

    func installedIDs(in models: [VoiceModel]) -> Set<String> {
        Set(models.filter { !$0.isSystem && storage.isInstalled($0.id) }.map(\.id))
    }

    /// Starts a download. The returned task finishes when the download does; the UI ignores it.
    @discardableResult
    func start(_ model: VoiceModel) -> Task<Void, Never>? {
        switch state(for: model) {
        case .notInstalled, .failed: break
        default: return nil
        }
        apply(.start(total: model.sizeBytes), to: model.id)
        jobs[model.id] = Job(model: model)
        return Task { await run(model) }
    }

    /// Takes up the downloads that were running when the app went away: the models with a `.downloading` marker.
    func restore(_ models: [VoiceModel]) {
        for model in models where !model.isSystem && storage.isDownloading(model.id) { start(model) }
    }

    /// Stops the download and throws away what was fetched.
    func cancel(_ model: VoiceModel) {
        let id = model.id
        guard jobs[id] != nil else { return }
        jobs[id] = nil
        apply(.cancel, to: id)
        try? storage.delete(id)
        let storage = storage
        Task { [transport] in
            await transport.cancel(modelID: id)
            // A file that landed while the tasks were stopping.
            if jobs[id] == nil { try? storage.delete(id) }
        }
        onFinished?(id, .cancelled)
        ends.removeValue(forKey: id)?.resume()
    }

    /// Removes an installed model or a failed attempt. A download in flight is cancelled instead.
    func delete(_ model: VoiceModel) throws {
        if jobs[model.id] != nil {
            cancel(model)
            return
        }
        try storage.delete(model.id)
        apply(.delete, to: model.id)
    }

    // MARK: Running a job

    private func run(_ model: VoiceModel) async {
        let id = model.id
        guard jobs[id] != nil else { return }
        do {
            try storage.prepareRoot()
            try storage.markDownloading(id)
            let live = await transport.livePaths(modelID: id)
            guard jobs[id] != nil else { return }
            var missing: [VoiceModelFile] = []
            for file in model.files {
                if Self.hasFile(file, at: storage.partialFileURL(id: id, path: file.path)) {
                    arrive(id, file.path)
                } else if !live.contains(file.path) {
                    missing.append(file)
                }
            }
            let needed = missing.reduce(Int64(0)) { $0 + $1.sizeBytes }
            if let free = storage.freeSpaceBytes(), free < needed + needed / 10 {
                throw LocalModelError.insufficientSpace(neededBytes: needed, freeBytes: free)
            }
            for file in missing { transport.enqueue(modelID: id, file: file) }
            advance(id)
            guard jobs[id] != nil else { return }
            await withCheckedContinuation { ends[id] = $0 }
        } catch {
            fail(id, error.localizedDescription)
        }
    }

    private func handle(_ callback: DownloadCallback) {
        guard let entry = callback.entryID, let id = DownloadTaskTag.voiceModelID(of: entry), jobs[id] != nil else { return }
        switch callback {
        case .progress(_, let path, let written):
            if var job = jobs[id] {
                job.received[path] = max(job.received[path] ?? 0, written)
                jobs[id] = job
            }
            reportProgress(id)
        case .fileFinished(_, let path):
            arrive(id, path)
            advance(id)
        case .fileFailed(_, _, let message):
            fail(id, message)
        case .fileCancelled, .backgroundEventsFinished:
            break
        }
    }

    /// A file has all its bytes: check it, unless a check of it is already running.
    private func arrive(_ id: String, _ path: String) {
        guard var job = jobs[id], let file = job.model.files.first(where: { $0.path == path }),
              !job.checking.contains(path) else { return }
        job.arrived.insert(path)
        job.checking.insert(path)
        jobs[id] = job
        Task { await check(id, file) }
    }

    private func check(_ id: String, _ file: VoiceModelFile) async {
        do {
            try await Self.verify(file, at: storage.partialFileURL(id: id, path: file.path))
        } catch {
            if jobs[id] != nil { fail(id, error.localizedDescription) }
            return
        }
        guard jobs[id] != nil else { return }
        jobs[id]?.verified.insert(file.path)
        advance(id)
    }

    /// Moves a job along: every file here is "downloaded", every file checked installs the model.
    private func advance(_ id: String) {
        guard let job = jobs[id] else { return }
        let total = job.model.files.count
        if job.arrived.count == total { apply(.downloaded, to: id) } else { reportProgress(id) }
        if job.verified.count == total { install(id) }
    }

    private func reportProgress(_ id: String) {
        guard let job = jobs[id], case .downloading(let shown, _) = states[id] ?? .notInstalled,
              job.receivedBytes > shown else { return }
        apply(.progress(received: job.receivedBytes, total: job.model.sizeBytes), to: id)
    }

    private func install(_ id: String) {
        guard let job = jobs[id] else { return }
        jobs[id] = nil
        let model = job.model
        do {
            let fm = FileManager.default
            for file in model.files {
                let final = storage.fileURL(id: id, path: file.path)
                try fm.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: final.path) { try fm.removeItem(at: final) }
                try fm.moveItem(at: storage.partialFileURL(id: id, path: file.path), to: final)
            }
            try storage.writeManifest(VoiceInstalledManifest(
                id: id, files: model.files.map { .init(path: $0.path, size: $0.sizeBytes) }, completedAt: Date()))
            storage.clearDownloading(id)
            storage.removePartial(id)
            apply(.verified, to: id)
            onFinished?(id, .installed)
            ends.removeValue(forKey: id)?.resume()
        } catch {
            jobs[id] = job
            fail(id, error.localizedDescription)
        }
    }

    /// Ends the job with a message. Files that passed their checks stay for Try Again.
    private func fail(_ id: String, _ message: String) {
        guard jobs[id] != nil || states[id]?.isActive == true else { return }
        jobs[id] = nil
        apply(.fail(message), to: id)
        storage.clearDownloading(id)
        Task { [transport] in await transport.cancel(modelID: id) }
        onFinished?(id, .failed)
        ends.removeValue(forKey: id)?.resume()
    }

    private func apply(_ event: ModelDownloadEvent, to id: String) {
        states[id] = (states[id] ?? .notInstalled).reduce(event)
    }

    private static func hasFile(_ file: VoiceModelFile, at url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return size == file.sizeBytes
    }

    /// Size, then sha256 where the catalog pins one. A bad file is deleted so the next attempt fetches it again.
    private static func verify(_ file: VoiceModelFile, at url: URL) async throws {
        guard hasFile(file, at: url) else {
            try? FileManager.default.removeItem(at: url)
            throw LocalModelError.sizeMismatch(file.path)
        }
        guard let expected = file.sha256 else { return }
        let actual = try await Task.detached(priority: .utility) { try ModelInstaller.sha256Hex(of: url) }.value
        guard actual == expected.lowercased() else {
            try? FileManager.default.removeItem(at: url)
            throw LocalModelError.checksumMismatch(file.path)
        }
    }
}
