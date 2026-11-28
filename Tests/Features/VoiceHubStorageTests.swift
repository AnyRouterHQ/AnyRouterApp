import Foundation
import Testing
@testable import AnyRouter

/// Settings › Local Models › Storage lists the voice folder too: a voice model shows with its catalog title and size,
/// and deleting the selected one hands speech back to System so nothing points at a model that is gone.
@MainActor
struct VoiceHubStorageTests {
    private let small = VoiceFixtures.model("whisper-small")

    private func hub(root: URL) -> VoiceHub {
        VoiceHub(
            settings: VoiceSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            downloader: VoiceModelDownloader(storage: VoiceModelStorage(root: root)), catalog: { [small] })
    }

    @Test func theStorageListNamesVoiceModelsAndDeletingTheSelectedOneFallsBackToSystem() async throws {
        let root = makeTempDirectory().appending(path: "Voice", directoryHint: .isDirectory)
        let hub = hub(root: root)
        let storage = hub.downloader.storage
        try storage.writeManifest(VoiceInstalledManifest(id: small.id, files: [], completedAt: Date(timeIntervalSince1970: 0)))
        try Data("weights".utf8).write(to: storage.directory(for: small.id).appending(path: "model.bin"))
        let stray = storage.directory(for: "stray")
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        hub.select(small)

        await hub.rescanStorage()
        let rows = hub.storageItems
        #expect(rows.map(\.name) == ["whisper-small", "stray"] && rows.map(\.kind) == [.installed, .orphan])
        #expect(rows[0].bytes > 0)

        await hub.deleteStorageItem(rows[0])
        #expect(!storage.isInstalled(small.id), "its files are gone")
        #expect(hub.selectedID(.stt) == VoiceModel.systemID, "speech falls back to System")
        let leftover = try #require(hub.storageItems.first)
        await hub.deleteStorageItem(leftover)
        #expect(hub.storageItems.isEmpty, "a folder the catalog does not name is deleted too")
    }

    @Test func aRunningVoiceDownloadIsNotDeletedFromTheList() async {
        let hub = hub(root: makeTempDirectory())
        let running = StorageInventoryLogic.Item(
            id: "x", name: "x", bytes: 1, kind: .partial, folders: ["x"], source: nil, isRunning: true)
        let folder = hub.downloader.storage.directory(for: "x")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await hub.deleteStorageItem(running)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }
}
