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

    /// Bytes on disk for an installed model, from its manifest.
    func installedBytes(_ id: String) -> Int64 { manifest(id)?.sizeBytes ?? 0 }

    private func manifestURL(_ id: String) -> URL {
        directory(for: id).appending(path: Self.manifestName)
    }
}
