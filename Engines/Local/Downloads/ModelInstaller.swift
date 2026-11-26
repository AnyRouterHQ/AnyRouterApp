import CryptoKit
import Foundation

/// Checks downloaded files and moves them into place. Blocking and CPU heavy: call off the main actor.
enum ModelInstaller {
    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var finished = false
        while !finished {
            try autoreleasepool {
                let chunk = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
                if chunk.isEmpty { finished = true } else { hasher.update(data: chunk) }
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Verifies size (and sha256 where the repo lists one), then installs. A bad file is deleted so a retry fetches it again.
    static func verifyAndInstall(_ job: DownloadJobRecord, storage: LocalModelStorage, now: Date = Date()) throws {
        let fm = FileManager.default
        let id = job.entry.id
        for file in job.files {
            let url = storage.partialFileURL(forEntryID: id, path: file.path)
            let size = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            if file.size > 0, size != file.size {
                try? fm.removeItem(at: url)
                throw LocalModelError.sizeMismatch(file.path)
            }
            if let expected = file.sha256, try sha256Hex(of: url) != expected.lowercased() {
                try? fm.removeItem(at: url)
                throw LocalModelError.checksumMismatch(file.path)
            }
        }
        let manifest = InstalledManifest(
            entryID: id, repo: job.entry.repo, format: job.entry.format, revision: job.entry.revision,
            files: job.files.map { .init(path: $0.path, size: $0.size) }, completedAt: now)
        try storage.finalizeInstall(manifest)
        storage.removeJob(entryID: id)
    }
}
