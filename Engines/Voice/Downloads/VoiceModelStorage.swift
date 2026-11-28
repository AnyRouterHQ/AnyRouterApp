import Foundation

/// What a finished install leaves in the model's folder. Its presence means "installed".
struct VoiceInstalledManifest: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        var path: String
        var size: Int64
    }

    var id: String
    var files: [File]
    var completedAt: Date

    var sizeBytes: Int64 { files.reduce(0) { $0 + $1.size } }
}

/// Where voice models live: `Application Support/Voice/<id>/`, kept out of iCloud backup. The folder is what an engine
/// loads (WhisperKit's `modelFolder`), so file paths inside it are the catalog's paths.
struct VoiceModelStorage: Sendable {
    static let manifestName = ".installed.json"
    /// Present while a download of the model is running, so a relaunch knows to take it up again.
    static let downloadingName = ".downloading"

    let root: URL
    private let base: LocalModelStorage

    init(root: URL = VoiceModelStorage.defaultRoot) {
        self.root = root
        base = LocalModelStorage(root: root)
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Voice", directoryHint: .isDirectory)
    }

    func directory(for id: String) -> URL {
        root.appending(path: LocalModelStorage.directoryName(forEntryID: id), directoryHint: .isDirectory)
    }

    func fileURL(id: String, path: String) -> URL { directory(for: id).appending(path: path) }

    /// Where a file waits, complete, until the whole model has been checked. The background session puts it there.
    func partialFileURL(id: String, path: String) -> URL { base.partialFileURL(forEntryID: id, path: path) }

    func isDownloading(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: downloadingURL(id).path)
    }

    func markDownloading(_ id: String) throws {
        try FileManager.default.createDirectory(at: directory(for: id), withIntermediateDirectories: true)
        try Data().write(to: downloadingURL(id))
    }

    func removePartial(_ id: String) {
        try? FileManager.default.removeItem(at: base.partialDirectory(forEntryID: id))
    }

    func clearDownloading(_ id: String) {
        try? FileManager.default.removeItem(at: downloadingURL(id))
    }

    func isInstalled(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: manifestURL(id).path)
    }

    func manifest(_ id: String) -> VoiceInstalledManifest? {
        guard let data = try? Data(contentsOf: manifestURL(id)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(VoiceInstalledManifest.self, from: data)
    }

    func prepareRoot() throws { try base.prepareRoot() }

    func freeSpaceBytes() -> Int64? { base.freeSpaceBytes() }

    /// The manifest goes last, so a crash never leaves a half install marked as done.
    func writeManifest(_ manifest: VoiceInstalledManifest) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory(for: manifest.id), withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: manifestURL(manifest.id), options: .atomic)
    }

    func delete(_ id: String) throws {
        let dir = directory(for: id)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }

    /// Every folder under the voice root, in the shape the storage list and the launch clean-up read. A voice download's
    /// record is its `.downloading` marker, not a job file.
    func folders() -> [ModelFolder] {
        base.folders().map { folder in
            var folder = folder
            let marker = root.appending(path: folder.name).appending(path: Self.downloadingName)
            folder.hasJob = folder.hasJob || FileManager.default.fileExists(atPath: marker.path)
            return folder
        }
    }

    /// Removes one folder by name, for a voice model the catalog no longer lists or files no record explains.
    func delete(folder name: String) throws { try base.delete(folder: name) }

    /// The launch clean-up, by the same rule as the chat models (`StorageInventoryLogic.leftovers`): no finished install,
    /// no `.downloading` marker, no download in flight. Returns the folders it removed. Safe to run again.
    func removeLeftovers(running: Set<String>) -> [String] {
        let names = StorageInventoryLogic.leftovers(folders(), running: running)
        for name in names { try? base.delete(folder: name) }
        return names
    }

    /// Bytes on disk for an installed model, from its manifest.
    func installedBytes(_ id: String) -> Int64 { manifest(id)?.sizeBytes ?? 0 }

    private func downloadingURL(_ id: String) -> URL {
        directory(for: id).appending(path: Self.downloadingName)
    }

    private func manifestURL(_ id: String) -> URL {
        directory(for: id).appending(path: Self.manifestName)
    }
}
