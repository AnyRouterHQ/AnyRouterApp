import Foundation
import Testing
@testable import AnyRouter

/// The models folder read from disk on a temp root: what the storage list and the launch clean-up see, and that the
/// clean-up removes what a cancelled download left without ever touching an installed model.
struct ModelFolderTests {
    private func makeStorage() -> LocalModelStorage {
        LocalModelStorage(root: makeTempDirectory().appending(path: "Models", directoryHint: .isDirectory))
    }

    private func install(_ storage: LocalModelStorage, _ entry: CatalogEntry) throws {
        let manifest = InstalledManifest(entryID: entry.id, repo: entry.repo, format: entry.format, revision: nil,
                                         files: [.init(path: "m.gguf", size: 5)], completedAt: Date(timeIntervalSince1970: 0))
        let dir = storage.directory(forEntryID: entry.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: dir.appending(path: "m.gguf"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: storage.manifestURL(forEntryID: entry.id))
    }

    private func leavePartial(_ storage: LocalModelStorage, folder: String) throws {
        let partial = storage.root.appending(path: folder).appending(path: LocalModelStorage.partialName)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: partial.appending(path: "m.gguf.resume"))
    }

    private func names(_ storage: LocalModelStorage) -> [String] { storage.folders().map(\.name) }

    @Test func eachFolderSaysWhatItHoldsFromTheFilesOnDisk() throws {
        let storage = makeStorage()
        try storage.prepareRoot()
        let model = sampleGGUF(title: "Installed")
        try install(storage, model)
        let started = sampleGGUF(file: "started.gguf", title: "Started")
        try storage.writeJob(DownloadJobRecord(entry: started, files: []))
        try leavePartial(storage, folder: storage.directory(forEntryID: started.id).lastPathComponent)
        let old = storage.root.appending(path: "old")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: old.appending(path: LocalModelStorage.manifestName))
        try Data("stray".utf8).write(to: storage.root.appending(path: "stray.txt"))

        let folders = storage.folders()
        #expect(folders.count == 3, "a loose file is not a folder")
        let installed = try #require(folders.first { $0.name == storage.directory(forEntryID: model.id).lastPathComponent })
        #expect(installed.hasManifest && installed.manifest?.entryID == model.id && !installed.hasJob && installed.bytes > 0)
        let partial = try #require(folders.first { $0.job != nil })
        #expect(partial.job?.entry.id == started.id && partial.hasJob && !partial.hasManifest)
        let unreadable = try #require(folders.first { $0.name == "old" })
        #expect(unreadable.hasManifest && unreadable.manifest == nil, "an unreadable manifest still counts as one")
    }

    @Test func aFolderIsDeletedByNameAndANameOutsideTheRootIsRefused() throws {
        let storage = makeStorage()
        try leavePartial(storage, folder: "gone")
        try storage.delete(folder: "gone")
        #expect(names(storage).isEmpty)
        try storage.delete(folder: "never-there")
        for bad in ["", ".", "..", "a/b"] {
            #expect(throws: CocoaError.self) { try storage.delete(folder: bad) }
        }
    }

    @Test func theLaunchCleanUpRemovesWhatAForgottenDownloadLeftAndNothingElseTwice() throws {
        let storage = makeStorage()
        try storage.prepareRoot()
        let model = sampleGGUF(title: "Installed")
        try install(storage, model)
        let modelFolder = storage.directory(forEntryID: model.id).lastPathComponent
        try leavePartial(storage, folder: modelFolder)
        let paused = sampleGGUF(file: "paused.gguf", title: "Paused")
        try storage.writeJob(DownloadJobRecord(entry: paused, files: []))
        let pausedFolder = storage.directory(forEntryID: paused.id).lastPathComponent
        try leavePartial(storage, folder: "forgotten")
        try leavePartial(storage, folder: "live")
        try FileManager.default.createDirectory(at: storage.root.appending(path: "empty"), withIntermediateDirectories: true)

        #expect(storage.removeLeftovers(running: ["live"]).sorted() == ["empty", "forgotten"])
        #expect(names(storage) == [modelFolder, pausedFolder, "live"].sorted())
        #expect(storage.isInstalled(entryID: model.id), "an installed model is never touched")
        #expect(storage.removeLeftovers(running: ["live"]).isEmpty, "a second run finds nothing")
    }
}
