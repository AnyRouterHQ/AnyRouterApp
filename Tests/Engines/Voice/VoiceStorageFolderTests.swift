import Foundation
import Testing
@testable import AnyRouter

/// The voice folder read from disk on a temp root, by the same rules as the chat models: a running or interrupted voice
/// download (its `.downloading` marker) and an installed voice model are kept; what a cancelled or failed download left goes.
struct VoiceStorageFolderTests {
    private func makeStorage() -> VoiceModelStorage {
        VoiceModelStorage(root: makeTempDirectory().appending(path: "Voice", directoryHint: .isDirectory))
    }

    private func leavePartial(_ storage: VoiceModelStorage, id: String) throws {
        let url = storage.partialFileURL(id: id, path: "model.bin")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("half".utf8).write(to: url)
    }

    private func names(_ storage: VoiceModelStorage) -> [String] { storage.folders().map(\.name) }

    @Test func aDownloadMarkerCountsAsTheDownloadRecord() throws {
        let storage = makeStorage()
        try storage.prepareRoot()
        try storage.writeManifest(VoiceInstalledManifest(id: "whisper-small", files: [], completedAt: Date(timeIntervalSince1970: 0)))
        try storage.markDownloading("kokoro")
        try leavePartial(storage, id: "kokoro")
        let folders = storage.folders()
        let installed = try #require(folders.first { $0.name == "whisper-small" })
        #expect(installed.hasManifest && !installed.hasJob)
        let downloading = try #require(folders.first { $0.name == "kokoro" })
        #expect(downloading.hasJob && !downloading.hasManifest && downloading.bytes > 0)
    }

    @Test func theLaunchCleanUpRemovesWhatACancelledOrFailedVoiceDownloadLeftAndNothingElse() throws {
        let storage = makeStorage()
        try storage.prepareRoot()
        try storage.writeManifest(VoiceInstalledManifest(id: "whisper-small", files: [], completedAt: Date(timeIntervalSince1970: 0)))
        try storage.markDownloading("kokoro")
        try leavePartial(storage, id: "failed-once")
        try leavePartial(storage, id: "live")
        try FileManager.default.createDirectory(at: storage.directory(for: "empty"), withIntermediateDirectories: true)

        #expect(storage.removeLeftovers(running: ["live"]).sorted() == ["empty", "failed-once"])
        #expect(names(storage) == ["kokoro", "live", "whisper-small"])
        #expect(storage.isInstalled("whisper-small"), "an installed voice model is never touched")
        #expect(storage.removeLeftovers(running: ["live"]).isEmpty, "a second run finds nothing")
    }

    /// A failed download keeps its record and its verified files, so the clean-up never costs the user the download
    /// again. Once the record goes (Cancel, Delete), the clean-up removes what is left.
    @Test func aFailedDownloadKeepsItsFilesUntilItsRecordGoes() throws {
        let storage = makeStorage()
        try storage.prepareRoot()
        try storage.markDownloading("kokoro")
        try leavePartial(storage, id: "kokoro")
        storage.keepFailure("kokoro", message: "The network connection was lost.")
        #expect(storage.failure("kokoro") == "The network connection was lost.")
        #expect(storage.folders().first?.hasJob == true, "it shows under Unfinished downloads")
        #expect(storage.removeLeftovers(running: []).isEmpty, "the clean-up keeps a failed download's files")

        storage.clearDownloading("kokoro")
        #expect(storage.removeLeftovers(running: []) == ["kokoro"], "without its record it is a leftover")
    }

    @Test func aFailureWithNothingVerifiedKeepsNoRecord() throws {
        let storage = makeStorage()
        try storage.markDownloading("tiny")
        storage.keepFailure("tiny", message: "Not enough space.")
        #expect(!storage.isDownloading("tiny") && storage.failure("tiny") == nil)
        try storage.markDownloading("tiny")
        #expect(storage.failure("tiny") == nil, "a new attempt is a plain downloading marker again")
    }

    @Test func aFolderTheCatalogDoesNotNameIsDeletedByName() throws {
        let storage = makeStorage()
        try leavePartial(storage, id: "gone")
        try storage.delete(folder: "gone")
        #expect(names(storage).isEmpty)
        #expect(throws: CocoaError.self) { try storage.delete(folder: "..") }
    }
}
