import Foundation

/// Files of attachments, one folder per thread: `Application Support/attachments/<thread id>/<id>.<ext>`.
/// New attachments wait in `_pending` until the first send creates the thread.
struct AttachmentStore: Sendable {
    static let pendingFolder = "_pending"

    let root: URL

    /// The app's own store. Tests pass a temporary folder instead.
    static let shared = AttachmentStore(root: defaultRoot)

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "attachments", directoryHint: .isDirectory)
    }

    init(root: URL) { self.root = root }

    /// Writes `data` into `folder` and returns the path relative to the root.
    func write(_ data: Data, id: UUID, fileExtension: String, folder: String = AttachmentStore.pendingFolder) throws -> String {
        let directory = root.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var relative = "\(folder)/\(id.uuidString)"
        if !fileExtension.isEmpty { relative += ".\(fileExtension)" }
        let url = root.appending(path: relative)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Chat files are not worth backing up to iCloud.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = url
        try? excluded.setResourceValues(values)
        return relative
    }

    func data(for attachment: ChatAttachment) -> Data? {
        try? Data(contentsOf: attachment.url(in: root))
    }

    /// Text read from the attachment when it was added. What the `read_attachment` tool returns.
    func extractedText(for attachment: ChatAttachment) -> String? { attachment.extractedText }

    /// Moves a pending attachment into its thread's folder.
    func adopt(_ attachment: ChatAttachment, intoThread thread: UUID) throws -> ChatAttachment {
        let name = (attachment.relativePath as NSString).lastPathComponent
        let folder = thread.uuidString
        // Already there (a send that failed halfway): moving it onto itself would delete it.
        if attachment.relativePath.hasPrefix(folder + "/") { return attachment }
        let directory = root.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: attachment.url(in: root), to: destination)
        var moved = attachment
        moved.relativePath = "\(folder)/\(name)"
        return moved
    }

    func exists(_ attachment: ChatAttachment) -> Bool {
        FileManager.default.fileExists(atPath: attachment.url(in: root).path)
    }

    func remove(_ attachment: ChatAttachment) {
        try? FileManager.default.removeItem(at: attachment.url(in: root))
    }

    /// Deletes every file of a thread. Called when the thread is deleted.
    func deleteThread(_ thread: UUID) {
        try? FileManager.default.removeItem(at: root.appending(path: thread.uuidString, directoryHint: .isDirectory))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Drops files that were picked but never sent, for example after the app was closed.
    func purgePending() {
        try? FileManager.default.removeItem(at: root.appending(path: Self.pendingFolder, directoryHint: .isDirectory))
    }
}
