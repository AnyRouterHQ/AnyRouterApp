import CryptoKit
import Foundation
import Testing
@testable import AnyRouter

struct LocalModelStorageTests {
    private func makeStorage() -> LocalModelStorage {
        LocalModelStorage(root: makeTempDirectory().appending(path: "Models", directoryHint: .isDirectory))
    }

    private func stage(_ storage: LocalModelStorage, entry: CatalogEntry, files: [String: String]) throws {
        for (path, text) in files {
            let url = storage.partialFileURL(forEntryID: entry.id, path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }

    private func job(_ entry: CatalogEntry, _ files: [String: String], withChecksums: Bool = true) -> DownloadJobRecord {
        let listing = files.sorted { $0.key < $1.key }.map { path, text in
            let sha = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            return HFFile(path: path, size: Int64(text.utf8.count), sha256: withChecksums ? sha : nil)
        }
        return DownloadJobRecord(entry: entry, files: listing)
    }

    @Test func directoryNamesAreFlatAndSafe() {
        let name = LocalModelStorage.directoryName(forEntryID: "gguf/org/Model (1)/a b.gguf")
        #expect(!name.contains("/"))
        #expect(!name.contains(" "))
        #expect(name == "gguf--org--Model__1_--a_b.gguf")
        #expect(LocalModelStorage.directoryName(forEntryID: "mlx/org/m-4bit") == "mlx--org--m-4bit")
    }

    @Test func differentEntriesOfOneRepoGetDifferentFolders() {
        let storage = makeStorage()
        let q4 = sampleGGUF(file: "m-Q4_K_M.gguf")
        let q8 = sampleGGUF(file: "m-Q8_0.gguf")
        #expect(storage.directory(forEntryID: q4.id) != storage.directory(forEntryID: q8.id))
    }

    @Test func aModelIsInstalledOnlyAfterFinalizeWritesTheManifest() throws {
        let storage = makeStorage()
        let entry = sampleGGUF()
        try stage(storage, entry: entry, files: ["model-Q4_K_M.gguf": "weights"])
        #expect(!storage.isInstalled(entryID: entry.id), "staged files alone are not an install")

        let record = job(entry, ["model-Q4_K_M.gguf": "weights"])
        try ModelInstaller.verifyAndInstall(record, storage: storage)
        #expect(storage.isInstalled(entryID: entry.id))
        let final = storage.fileURL(forEntryID: entry.id, path: "model-Q4_K_M.gguf")
        #expect(try String(contentsOf: final, encoding: .utf8) == "weights")
        #expect(!FileManager.default.fileExists(atPath: storage.partialDirectory(forEntryID: entry.id).path))
        let manifest = try #require(storage.readManifest(entryID: entry.id))
        #expect(manifest.files == [.init(path: "model-Q4_K_M.gguf", size: 7)])
        #expect(manifest.format == .gguf)
    }

    @Test func nestedMLXFilesLandInsideTheSnapshotFolder() throws {
        let storage = makeStorage()
        let entry = sampleMLX()
        let files = ["config.json": "{}", "weights/model.safetensors": "abc"]
        try stage(storage, entry: entry, files: files)
        try ModelInstaller.verifyAndInstall(job(entry, files), storage: storage)
        let dir = storage.directory(forEntryID: entry.id)
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "config.json").path))
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "weights/model.safetensors").path))
    }

    @Test func installedManifestsListEveryFinishedModelInIDOrder() throws {
        let storage = makeStorage()
        let b = sampleMLX(repo: "org/b")
        let a = sampleMLX(repo: "org/a")
        for entry in [b, a] {
            try stage(storage, entry: entry, files: ["config.json": "{}"])
            try ModelInstaller.verifyAndInstall(job(entry, ["config.json": "{}"]), storage: storage)
        }
        #expect(storage.installedManifests().map(\.entryID) == [a.id, b.id])
    }

    @Test func deleteRemovesTheModelFromDiskAndFromTheInstalledList() throws {
        let storage = makeStorage()
        let entry = sampleGGUF()
        try stage(storage, entry: entry, files: ["model-Q4_K_M.gguf": "weights"])
        try ModelInstaller.verifyAndInstall(job(entry, ["model-Q4_K_M.gguf": "weights"]), storage: storage)
        try storage.delete(entryID: entry.id)
        #expect(!storage.isInstalled(entryID: entry.id))
        #expect(storage.installedManifests().isEmpty)
        try storage.delete(entryID: entry.id) // deleting twice is fine
    }

    @Test func discardPartialKeepsAnInstalledModelAndDropsAnUnfinishedOne() throws {
        let storage = makeStorage()
        let done = sampleMLX(repo: "org/done")
        let half = sampleMLX(repo: "org/half")
        try stage(storage, entry: done, files: ["config.json": "{}"])
        try ModelInstaller.verifyAndInstall(job(done, ["config.json": "{}"]), storage: storage)
        try stage(storage, entry: half, files: ["model.safetensors": "partial"])

        storage.discardPartial(entryID: done.id)
        storage.discardPartial(entryID: half.id)
        #expect(storage.isInstalled(entryID: done.id))
        #expect(!FileManager.default.fileExists(atPath: storage.directory(forEntryID: half.id).path))
    }

    @Test func diskUsageCountsTheModelFolderAndTheRoot() throws {
        let storage = makeStorage()
        let entry = sampleGGUF()
        let text = String(repeating: "x", count: 20_000)
        try stage(storage, entry: entry, files: ["model-Q4_K_M.gguf": text])
        try ModelInstaller.verifyAndInstall(job(entry, ["model-Q4_K_M.gguf": text]), storage: storage)
        #expect(storage.diskUsageBytes(entryID: entry.id) >= 20_000)
        #expect(storage.totalDiskUsageBytes() >= storage.diskUsageBytes(entryID: entry.id))
        #expect(storage.diskUsageBytes(entryID: "gguf/none/none/none.gguf") == 0)
    }

    @Test func prepareRootExcludesModelsFromBackup() throws {
        let storage = makeStorage()
        try storage.prepareRoot()
        let values = try storage.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func jobsRoundTripSoARelaunchCanFindUnfinishedDownloads() throws {
        let storage = makeStorage()
        let entry = sampleMLX()
        let record = job(entry, ["config.json": "{}", "model.safetensors": "abc"])
        try storage.writeJob(record)
        #expect(storage.pendingJobs() == [record])
        storage.removeJob(entryID: entry.id)
        #expect(storage.pendingJobs().isEmpty)
    }
}

struct ModelInstallerTests {
    @Test func sha256MatchesAKnownDigest() throws {
        let url = makeTempDirectory().appending(path: "hello.txt")
        try Data("hello".utf8).write(to: url)
        #expect(try ModelInstaller.sha256Hex(of: url) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test func aCorruptFileIsRejectedAndDeletedSoItDownloadsAgain() throws {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let entry = sampleGGUF()
        let url = storage.partialFileURL(forEntryID: entry.id, path: "model-Q4_K_M.gguf")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: url)
        // Right size, wrong content.
        let record = DownloadJobRecord(
            entry: entry, files: [HFFile(path: "model-Q4_K_M.gguf", size: 5, sha256: String(repeating: "0", count: 64))])
        #expect(throws: LocalModelError.checksumMismatch("model-Q4_K_M.gguf")) {
            try ModelInstaller.verifyAndInstall(record, storage: storage)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!storage.isInstalled(entryID: entry.id))
    }

    @Test func aTruncatedFileFailsTheSizeCheck() throws {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let entry = sampleGGUF()
        let url = storage.partialFileURL(forEntryID: entry.id, path: "model-Q4_K_M.gguf")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("he".utf8).write(to: url)
        let record = DownloadJobRecord(entry: entry, files: [HFFile(path: "model-Q4_K_M.gguf", size: 5)])
        #expect(throws: LocalModelError.sizeMismatch("model-Q4_K_M.gguf")) {
            try ModelInstaller.verifyAndInstall(record, storage: storage)
        }
        #expect(!storage.isInstalled(entryID: entry.id))
    }

    @Test func anInstallWithABadFileLeavesNoManifestBehind() throws {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let entry = sampleMLX()
        let good = storage.partialFileURL(forEntryID: entry.id, path: "config.json")
        try FileManager.default.createDirectory(at: good.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: good)
        let record = DownloadJobRecord(entry: entry, files: [
            HFFile(path: "config.json", size: 2),
            HFFile(path: "model.safetensors", size: 9), // never downloaded
        ])
        #expect(throws: (any Error).self) { try ModelInstaller.verifyAndInstall(record, storage: storage) }
        #expect(!storage.isInstalled(entryID: entry.id))
    }
}
