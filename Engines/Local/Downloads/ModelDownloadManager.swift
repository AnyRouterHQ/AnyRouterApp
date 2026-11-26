import Foundation
import Observation

/// Downloads local models with a background `URLSession`, so a download keeps going when the app is suspended.
/// One model = one job; a job is one task per file. State per entry id is in `states`.
///
/// App wiring still to do (lane A, App/): hand the system's completion handler from
/// `application(_:handleEventsForBackgroundURLSession:completionHandler:)` to `backgroundCompletionHandler`,
/// and call `restore()` once at launch.
@MainActor @Observable
final class ModelDownloadManager {
    static let sessionIdentifier = "dev.anyrouter.app.models"

    private(set) var states: [String: ModelDownloadState] = [:]

    let storage: LocalModelStorage
    private let api: HuggingFaceAPI
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var jobs: [String: Job] = [:]
    /// Identifies the latest `start` per entry, so a start that was cancelled while the file listing loaded does nothing.
    @ObservationIgnored private var startTokens: [String: UUID] = [:]
    @ObservationIgnored var backgroundCompletionHandler: (@Sendable () -> Void)?

    private struct Job {
        var record: DownloadJobRecord
        var tracker: DownloadProgressTracker
    }

    init(storage: LocalModelStorage = LocalModelStorage(), api: HuggingFaceAPI = HuggingFaceAPI()) {
        self.storage = storage
        self.api = api
        let delegate = DownloadDelegate(storage: storage) { [weak self] callback in
            Task { @MainActor in self?.handle(callback) }
        }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
    }

    // MARK: Reading state

    func state(for entry: CatalogEntry) -> ModelDownloadState {
        states[entry.id] ?? .notInstalled
    }

    /// Sets installed / not installed from disk for entries with no download in flight. Call after loading the catalog.
    func refresh(entries: [CatalogEntry]) {
        for entry in entries where !(states[entry.id]?.isActive ?? false) {
            states[entry.id] = storage.isInstalled(entryID: entry.id) ? .installed : .notInstalled
        }
    }

    // MARK: Commands

    func start(_ entry: CatalogEntry) async {
        let id = entry.id
        switch states[id] ?? .notInstalled {
        case .notInstalled, .failed: break
        default: return
        }
        apply(.start(total: entry.sizeBytes ?? 0), to: id)
        let token = UUID()
        startTokens[id] = token
        do {
            try storage.prepareRoot()
            let listing = try await api.listFiles(repo: entry.repo, revision: entry.revision ?? "main")
            let files = try RepoFiles.downloadPlan(for: entry, files: listing)
            guard startTokens[id] == token else { return }
            let total = files.reduce(Int64(0)) { $0 + $1.size }
            if let free = storage.freeSpaceBytes(), free < total + total / 10 {
                throw LocalModelError.insufficientSpace(neededBytes: total, freeBytes: free)
            }
            let record = DownloadJobRecord(entry: entry, files: files)
            try storage.writeJob(record)
            var tracker = DownloadProgressTracker(files: files)
            // Files that finished in an earlier attempt are kept.
            for file in files where Self.partialIsComplete(file, entryID: id, storage: storage) {
                tracker.markFinished(path: file.path)
            }
            jobs[id] = Job(record: record, tracker: tracker)
            apply(.progress(received: tracker.receivedBytes, total: tracker.totalBytes), to: id)
            if tracker.isComplete {
                finishDownload(id)
            } else if case .paused = states[id] ?? .notInstalled {
                // Paused while the listing loaded: keep the job, `resume` starts the tasks.
            } else {
                for path in tracker.remainingPaths {
                    if let file = files.first(where: { $0.path == path }) { startTask(entry: entry, file: file) }
                }
            }
        } catch {
            if startTokens[id] == token { fail(id, message: error.localizedDescription) }
        }
    }

    func pause(_ entry: CatalogEntry) {
        let id = entry.id
        guard case .downloading = states[id] ?? .notInstalled else { return }
        apply(.pause, to: id)
        let storage = storage
        let session = session
        Task {
            for task in await session?.allTasks ?? [] {
                guard let tag = task.taskDescription.flatMap(DownloadTaskTag.init(encoded:)), tag.entryID == id,
                      let download = task as? URLSessionDownloadTask else { continue }
                if let data = await download.cancelByProducingResumeData() {
                    let url = storage.resumeDataURL(forEntryID: id, path: tag.path)
                    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: url)
                }
            }
        }
    }

    func resume(_ entry: CatalogEntry) {
        let id = entry.id
        guard case .paused = states[id] ?? .notInstalled, let job = jobs[id] else { return }
        apply(.resume, to: id)
        for path in job.tracker.remainingPaths {
            if let file = job.record.files.first(where: { $0.path == path }) { startTask(entry: job.record.entry, file: file) }
        }
    }

    /// Stops the download and throws away what was fetched.
    func cancel(_ entry: CatalogEntry) {
        let id = entry.id
        jobs[id] = nil
        startTokens[id] = nil
        apply(.cancel, to: id)
        Task { await discard(id) }
    }

    /// Removes an installed model (or a failed attempt) from disk.
    func delete(_ entry: CatalogEntry) throws {
        let id = entry.id
        if states[id]?.isActive ?? false {
            cancel(entry)
            return
        }
        try storage.delete(entryID: id)
        apply(.delete, to: id)
    }

    /// Reconnects to downloads the system kept running while the app was gone. Call once at launch.
    func restore() async {
        let live = await session?.allTasks ?? []
        let liveTags = Set(live.compactMap { $0.taskDescription.flatMap(DownloadTaskTag.init(encoded:)) })
        for record in storage.pendingJobs() {
            let id = record.entry.id
            if storage.isInstalled(entryID: id) {
                storage.removeJob(entryID: id)
                continue
            }
            guard jobs[id] == nil else { continue }
            var tracker = DownloadProgressTracker(files: record.files)
            for file in record.files where Self.partialIsComplete(file, entryID: id, storage: storage) {
                tracker.markFinished(path: file.path)
            }
            jobs[id] = Job(record: record, tracker: tracker)
            states[id] = .downloading(received: tracker.receivedBytes, total: tracker.totalBytes)
            if tracker.isComplete {
                finishDownload(id)
                continue
            }
            let missing = tracker.remainingPaths.filter { !liveTags.contains(DownloadTaskTag(entryID: id, path: $0)) }
            if missing.count == tracker.remainingPaths.count {
                // Nothing running for this job: wait for the user.
                states[id] = .paused(received: tracker.receivedBytes, total: tracker.totalBytes)
            } else {
                for path in missing {
                    if let file = record.files.first(where: { $0.path == path }) { startTask(entry: record.entry, file: file) }
                }
            }
        }
    }

    // MARK: Internals

    private func apply(_ event: ModelDownloadEvent, to id: String) {
        states[id] = (states[id] ?? .notInstalled).reduce(event)
    }

    private func isDownloading(_ id: String) -> Bool {
        if case .downloading = states[id] ?? .notInstalled { return true }
        return false
    }

    nonisolated private static func partialIsComplete(_ file: HFFile, entryID: String, storage: LocalModelStorage) -> Bool {
        let url = storage.partialFileURL(forEntryID: entryID, path: file.path)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return file.size > 0 && size == file.size
    }

    private func startTask(entry: CatalogEntry, file: HFFile) {
        guard let session else { return }
        let id = entry.id
        let resumeURL = storage.resumeDataURL(forEntryID: id, path: file.path)
        let task: URLSessionDownloadTask
        if let data = try? Data(contentsOf: resumeURL) {
            try? FileManager.default.removeItem(at: resumeURL)
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(
                with: api.resolveURL(repo: entry.repo, revision: entry.revision ?? "main", path: file.path))
        }
        task.taskDescription = DownloadTaskTag(entryID: id, path: file.path).encoded
        task.resume()
    }

    private func handle(_ callback: DownloadCallback) {
        switch callback {
        case .progress(let id, let path, let written):
            guard isDownloading(id), var job = jobs[id] else { return }
            job.tracker.update(path: path, receivedBytes: written)
            jobs[id] = job
            apply(.progress(received: job.tracker.receivedBytes, total: job.tracker.totalBytes), to: id)
        case .fileFinished(let id, let path):
            guard var job = jobs[id] else { return }
            job.tracker.markFinished(path: path)
            jobs[id] = job
            if job.tracker.isComplete {
                finishDownload(id)
            } else if isDownloading(id) {
                apply(.progress(received: job.tracker.receivedBytes, total: job.tracker.totalBytes), to: id)
            }
        case .fileFailed(let id, _, let message):
            guard isDownloading(id) else { return }
            fail(id, message: message)
        case .fileCancelled:
            break
        case .backgroundEventsFinished:
            let handler = backgroundCompletionHandler
            backgroundCompletionHandler = nil
            handler?()
        }
    }

    private func finishDownload(_ id: String) {
        guard let job = jobs[id] else { return }
        // A paused job whose last file landed anyway still finishes.
        if case .paused = states[id] ?? .notInstalled { apply(.resume, to: id) }
        apply(.downloaded, to: id)
        let storage = storage
        let record = job.record
        Task {
            let result: Result<Void, Error> = await Task.detached(priority: .utility) {
                Result { try ModelInstaller.verifyAndInstall(record, storage: storage) }
            }.value
            guard case .verifying = states[id] ?? .notInstalled else { return }
            switch result {
            case .success:
                jobs[id] = nil
                apply(.verified, to: id)
            case .failure(let error):
                // The bad file is gone; a retry downloads only that file again.
                fail(id, message: error.localizedDescription)
            }
        }
    }

    private func fail(_ id: String, message: String) {
        jobs[id] = nil
        apply(.fail(message), to: id)
        let session = session
        Task {
            for task in await session?.allTasks ?? [] {
                if let tag = task.taskDescription.flatMap(DownloadTaskTag.init(encoded:)), tag.entryID == id { task.cancel() }
            }
        }
    }

    private func discard(_ id: String) async {
        for task in await session?.allTasks ?? [] {
            if let tag = task.taskDescription.flatMap(DownloadTaskTag.init(encoded:)), tag.entryID == id { task.cancel() }
        }
        storage.discardPartial(entryID: id)
    }
}
