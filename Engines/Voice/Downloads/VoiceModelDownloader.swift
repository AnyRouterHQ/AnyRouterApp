import CryptoKit
import Foundation
import Observation

/// Gets one file from the network into a place the caller chooses. A seam so tests do not touch the network.
protocol VoiceFileFetching: Sendable {
    /// Downloads `url` to `destination`, replacing a file there, and reports the bytes received so far.
    /// Throws unless the server answers 200.
    func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws
}

struct URLSessionFileFetcher: VoiceFileFetching {
    private final class Progress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let report: @Sendable (Int64) -> Void
        init(_ report: @escaping @Sendable (Int64) -> Void) { self.report = report }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            report(totalBytesWritten)
        }

        // The async download call returns the file; there is nothing to do here.
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }

    func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let (location, response) = try await URLSession.shared.download(from: url, delegate: Progress(progress))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: location)
            throw LocalModelError.invalidResponse
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: location, to: destination)
    }
}

/// Downloads voice models, one file after another. The same `ModelDownloadState` machine as the chat models.
/// Voice models are folders of small and medium files (up to about 650 MB) from Hugging Face, so this uses a plain
/// foreground session, not the background session of `ModelDownloadManager` (GGUF and MLX repos). A file that finished
/// and passed its checks is kept, so Get after a failure or a closed app continues where it stopped.
@MainActor @Observable
final class VoiceModelDownloader {
    private(set) var states: [String: ModelDownloadState] = [:]

    let storage: VoiceModelStorage
    @ObservationIgnored private let fetcher: any VoiceFileFetching
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(storage: VoiceModelStorage = VoiceModelStorage(), fetcher: any VoiceFileFetching = URLSessionFileFetcher()) {
        self.storage = storage
        self.fetcher = fetcher
    }

    func state(for model: VoiceModel) -> ModelDownloadState {
        if model.isSystem { return .installed }
        return states[model.id] ?? (storage.isInstalled(model.id) ? .installed : .notInstalled)
    }

    func isInstalled(_ model: VoiceModel) -> Bool { state(for: model) == .installed }

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
        let task = Task { await run(model) }
        tasks[model.id] = task
        return task
    }

    /// Stops the download and throws away what was fetched.
    func cancel(_ model: VoiceModel) {
        tasks[model.id]?.cancel()
    }

    /// Removes an installed model or a failed attempt. A download in flight is cancelled instead.
    func delete(_ model: VoiceModel) throws {
        if states[model.id]?.isActive ?? false {
            cancel(model)
            return
        }
        try storage.delete(model.id)
        apply(.delete, to: model.id)
    }

    private func run(_ model: VoiceModel) async {
        let id = model.id
        defer { tasks[id] = nil }
        do {
            try storage.prepareRoot()
            let have = model.files.reduce(Int64(0)) { sum, file in sum + (Self.hasFile(file, at: storage.fileURL(id: id, path: file.path)) ? file.sizeBytes : 0) }
            let needed = model.sizeBytes - have
            if let free = storage.freeSpaceBytes(), free < needed + needed / 10 {
                throw LocalModelError.insufficientSpace(neededBytes: needed, freeBytes: free)
            }
            var done: Int64 = 0
            for file in model.files {
                try Task.checkCancellation()
                let final = storage.fileURL(id: id, path: file.path)
                if Self.hasFile(file, at: final) {
                    done += file.sizeBytes
                    continue
                }
                let part = final.appendingPathExtension("part")
                let before = done
                let total = model.sizeBytes
                try await fetcher.fetch(file.url, to: part) { [weak self] received in
                    Task { @MainActor in self?.report(id, received: before + received, total: total) }
                }
                try Task.checkCancellation()
                try await Self.verify(file, at: part)
                if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: final) }
                try FileManager.default.moveItem(at: part, to: final)
                done += file.sizeBytes
                report(id, received: done, total: total)
            }
            apply(.downloaded, to: id)
            try storage.writeManifest(VoiceInstalledManifest(
                id: id, files: model.files.map { .init(path: $0.path, size: $0.sizeBytes) }, completedAt: Date()))
            apply(.verified, to: id)
        } catch {
            if Task.isCancelled {
                try? storage.delete(id)
                apply(.cancel, to: id)
            } else {
                apply(.fail(error.localizedDescription), to: id)
            }
        }
    }

    /// Progress callbacks hop to the main actor and can arrive out of order; the bar never moves back.
    private func report(_ id: String, received: Int64, total: Int64) {
        guard case .downloading(let shown, _) = states[id] ?? .notInstalled, received > shown else { return }
        apply(.progress(received: received, total: total), to: id)
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
