import Foundation

/// Identifies one file download inside a background session. Stored in `URLSessionTask.taskDescription`
/// so the system can hand it back after the app was relaunched.
struct DownloadTaskTag: Hashable, Sendable {
    var entryID: String
    var path: String

    init(entryID: String, path: String) {
        self.entryID = entryID
        self.path = path
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        self.init(entryID: String(parts[0]), path: String(parts[1]))
    }

    var encoded: String { entryID + "\t" + path }
}

enum DownloadCallback: Sendable {
    case progress(entryID: String, path: String, writtenBytes: Int64)
    case fileFinished(entryID: String, path: String)
    case fileFailed(entryID: String, path: String, message: String)
    /// We cancelled the task (pause, cancel). Never an error.
    case fileCancelled(entryID: String, path: String)
    case backgroundEventsFinished
}

/// Runs on the session's delegate queue. Moves each finished file into `.partial` right away
/// (the system deletes it when the callback returns) and reports everything else to the manager.
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let storage: LocalModelStorage
    private let emit: @Sendable (DownloadCallback) -> Void

    init(storage: LocalModelStorage, emit: @escaping @Sendable (DownloadCallback) -> Void) {
        self.storage = storage
        self.emit = emit
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let tag = downloadTask.taskDescription.flatMap(DownloadTaskTag.init(encoded:)) else { return }
        emit(.progress(entryID: tag.entryID, path: tag.path, writtenBytes: totalBytesWritten))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let tag = downloadTask.taskDescription.flatMap(DownloadTaskTag.init(encoded:)) else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let error: LocalModelError = (http.statusCode == 401 || http.statusCode == 403)
                ? .gatedOrPrivate(tag.path) : .http(status: http.statusCode)
            emit(.fileFailed(entryID: tag.entryID, path: tag.path, message: error.localizedDescription))
            return
        }
        do {
            let fm = FileManager.default
            let destination = storage.partialFileURL(forEntryID: tag.entryID, path: tag.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: location, to: destination)
            emit(.fileFinished(entryID: tag.entryID, path: tag.path))
        } catch {
            emit(.fileFailed(entryID: tag.entryID, path: tag.path, message: error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // A finished file already reported itself in didFinishDownloadingTo.
        guard let error, let tag = task.taskDescription.flatMap(DownloadTaskTag.init(encoded:)) else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            emit(.fileCancelled(entryID: tag.entryID, path: tag.path))
            return
        }
        if let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            let url = storage.resumeDataURL(forEntryID: tag.entryID, path: tag.path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
        emit(.fileFailed(entryID: tag.entryID, path: tag.path, message: error.localizedDescription))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        emit(.backgroundEventsFinished)
    }
}
