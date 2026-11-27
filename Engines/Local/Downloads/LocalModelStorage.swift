import Foundation

/// What a finished install leaves next to the model files. Its presence means "installed".
struct InstalledManifest: Codable, Sendable, Equatable {
    struct File: Codable, Sendable, Equatable {
        var path: String
        var size: Int64
    }

    var entryID: String
    var repo: String
    var format: LocalModelFormat
    var revision: String?
    var files: [File]
    var completedAt: Date
}

/// A download that has started: which entry and exactly which files, with sizes and checksums from the repo listing.
struct DownloadJobRecord: Codable, Sendable, Equatable {
    var entry: CatalogEntry
    var files: [HFFile]
}

/// Where local models live: `Application Support/Models/<entry dir>/`, kept out of iCloud backup.
/// GGUF: the `.gguf` file in that folder. MLX: the snapshot folder itself (config.json, safetensors, tokenizer).
struct LocalModelStorage: Sendable {
    static let manifestName = ".installed.json"
    static let partialName = ".partial"

    let root: URL

    init(root: URL = LocalModelStorage.defaultRoot) {
        self.root = root
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Models", directoryHint: .isDirectory)
    }

    // MARK: Paths

    /// Folder name for an entry id. Everything outside `[A-Za-z0-9._-]` becomes `_`, `/` becomes `--`.
    static func directoryName(forEntryID id: String) -> String {
        let slashed = id.replacingOccurrences(of: "/", with: "--")
        return String(slashed.map { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) ? $0 : "_" })
    }

    func directory(forEntryID id: String) -> URL {
        root.appending(path: Self.directoryName(forEntryID: id), directoryHint: .isDirectory)
    }

    func partialDirectory(forEntryID id: String) -> URL {
        directory(forEntryID: id).appending(path: Self.partialName, directoryHint: .isDirectory)
    }

    func manifestURL(forEntryID id: String) -> URL {
        directory(forEntryID: id).appending(path: Self.manifestName)
    }

    /// Where a repo file lives on disk, relative to the model folder. A GGUF its publisher renamed to `.gguf_file` (so
    /// tools that list `*.gguf` skip it) is saved as `.gguf` again.
    static func diskPath(forRepoPath path: String) -> String {
        path.hasSuffix(".gguf_file") ? String(path.dropLast("_file".count)) : path
    }

    /// Final location of one file of an installed model. `path` is the file's path in the repo.
    func fileURL(forEntryID id: String, path: String) -> URL {
        directory(forEntryID: id).appending(path: Self.diskPath(forRepoPath: path))
    }

    /// Where a file waits until the whole model has been verified.
    func partialFileURL(forEntryID id: String, path: String) -> URL {
        partialDirectory(forEntryID: id).appending(path: Self.diskPath(forRepoPath: path))
    }

    func resumeDataURL(forEntryID id: String, path: String) -> URL {
        partialFileURL(forEntryID: id, path: path).appendingPathExtension("resume")
    }

    // MARK: Root

    /// Creates the root and marks it excluded from iCloud backup (models are re-downloadable and large).
    func prepareRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Free space on the models volume, or nil when the system does not say.
    func freeSpaceBytes() -> Int64? {
        let probe = FileManager.default.fileExists(atPath: root.path) ? root : root.deletingLastPathComponent()
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: Installed models

    func isInstalled(entryID id: String) -> Bool {
        FileManager.default.fileExists(atPath: manifestURL(forEntryID: id).path)
    }

    func readManifest(entryID id: String) -> InstalledManifest? {
        guard let data = try? Data(contentsOf: manifestURL(forEntryID: id)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InstalledManifest.self, from: data)
    }

    func installedManifests() -> [InstalledManifest] {
        let dirs = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appending(path: Self.manifestName)) else { return nil }
            return try? decoder.decode(InstalledManifest.self, from: data)
        }
        .sorted { $0.entryID < $1.entryID }
    }

    /// Moves verified files out of `.partial`, then writes the manifest last, so a crash never leaves a half install marked as done.
    func finalizeInstall(_ manifest: InstalledManifest) throws {
        let fm = FileManager.default
        for file in manifest.files {
            let from = partialFileURL(forEntryID: manifest.entryID, path: file.path)
            let to = fileURL(forEntryID: manifest.entryID, path: file.path)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.moveItem(at: from, to: to)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL(forEntryID: manifest.entryID), options: .atomic)
        try? fm.removeItem(at: partialDirectory(forEntryID: manifest.entryID))
    }

    // MARK: Download jobs

    private static let jobName = ".job.json"

    func writeJob(_ record: DownloadJobRecord) throws {
        let dir = directory(forEntryID: record.entry.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: dir.appending(path: Self.jobName), options: .atomic)
    }

    func removeJob(entryID id: String) {
        try? FileManager.default.removeItem(at: directory(forEntryID: id).appending(path: Self.jobName))
    }

    /// Jobs that started but were never finalized, e.g. after the app was killed.
    func pendingJobs() -> [DownloadJobRecord] {
        let dirs = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appending(path: Self.jobName)) else { return nil }
            return try? JSONDecoder().decode(DownloadJobRecord.self, from: data)
        }
        .sorted { $0.entry.id < $1.entry.id }
    }

    // MARK: Disk usage and delete

    func diskUsageBytes(entryID id: String) -> Int64 {
        Self.directorySize(directory(forEntryID: id))
    }

    func totalDiskUsageBytes() -> Int64 {
        Self.directorySize(root)
    }

    func delete(entryID id: String) throws {
        let dir = directory(forEntryID: id)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }

    /// Drops half-downloaded data, keeps nothing of an unfinished install.
    func discardPartial(entryID id: String) {
        try? FileManager.default.removeItem(at: partialDirectory(forEntryID: id))
        let dir = directory(forEntryID: id)
        if !isInstalled(entryID: id) { try? FileManager.default.removeItem(at: dir) }
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true, let size = values.totalFileAllocatedSize else { continue }
            total += Int64(size)
        }
        return total
    }
}
