import Foundation
import Testing
@testable import AnyRouter

/// Inkling 2 Mini reads photos only after the person adds the projector from the model's page. These tests pin what the
/// catalog says, what the download fetches, where the file lands, and when the app lists the vision capability.
struct PhotoAddOnTests {
    private static let projector = "mmproj-m-Q8_0.gguf"
    private static let weights = "m-IQ1_S.gguf"

    private func modelEntry(optional: Bool? = true) -> CatalogEntry {
        CatalogEntry(
            repo: "org/m-GGUF", format: .gguf, file: Self.weights, title: "M 26B", sizeBytes: 1_000_000_000, revision: "abc",
            vision: CatalogVision(mmprojFile: Self.projector, mmprojSize: 345_911_008, imageSide: nil, isOptional: optional))
    }

    private func memory(_ gigabytes: Double) -> DeviceMemory {
        DeviceMemory(budgetBytes: Int64(gigabytes * 1_000_000_000), physicalBytes: 0)
    }

    private func install(_ entry: CatalogEntry, files: [String], in storage: LocalModelStorage) throws {
        for path in files {
            let url = storage.partialFileURL(forEntryID: entry.id, path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("data".utf8).write(to: url)
        }
        try ModelInstaller.verifyAndInstall(
            DownloadJobRecord(entry: entry, files: files.map { HFFile(path: $0, size: 4) }), storage: storage)
    }

    private func decodeVision(_ json: String) throws -> CatalogVision {
        try JSONDecoder().decode(CatalogVision.self, from: Data(json.utf8))
    }

    // MARK: Catalog

    @Test func theOptionalFlagIsReadAndKeptAndOldEntriesStayRequired() throws {
        let optional = try decodeVision(##"{"mmprojFile":"p.gguf","mmprojSize":5,"optional":true}"##)
        #expect(optional.isOptional == true)
        let old = try decodeVision(##"{"mmprojFile":"p.gguf","mmprojSize":5,"imageSide":512}"##)
        #expect(old.isOptional == nil, "an entry written before the flag existed decodes as a projector that comes with the model")
        let written = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!written.contains("optional"), "the flag is not written when it was not set")
        #expect(try decodeVision(String(decoding: try JSONEncoder().encode(optional), as: UTF8.self)) == optional)
    }

    @Test func anOptionalProjectorIsADownloadOfItsOwnWithTheModelsRepoAndRevision() throws {
        let addOn = try #require(modelEntry().photoAddOn)
        #expect(addOn.id == "gguf/org/m-GGUF/\(Self.projector)")
        #expect(addOn.file == Self.projector)
        #expect(addOn.repo == "org/m-GGUF" && addOn.revision == "abc")
        #expect(addOn.sizeBytes == 345_911_008)
        #expect(addOn.format == .gguf)
        #expect(addOn.photoAddOn == nil && addOn.vision == nil)
        #expect(addOn.id != modelEntry().id)
    }

    @Test func onlyAnOptionalGGUFProjectorHasAnAddOn() {
        #expect(modelEntry(optional: false).photoAddOn == nil, "a required projector comes with the model")
        #expect(modelEntry(optional: nil).photoAddOn == nil)
        var text = modelEntry()
        text.vision = nil
        #expect(text.photoAddOn == nil)
        let mlx = CatalogEntry(repo: "org/m", format: .mlx, title: "M", vision: CatalogVision(mmprojFile: "p.gguf", isOptional: true))
        #expect(mlx.photoAddOn == nil)
    }

    @Test func aSizeWithAnOptionalProjectorDoesNotListVisionUntilTheProjectorIsInstalled() throws {
        let family = try JSONDecoder().decode(CatalogFamily.self, from: Data("""
        {"id":"f","name":"F","publisher":"P","line":"f","logo":"f","summary":"S","website":"https://example.org",
         "tags":["thinking"],"badges":[],"status":"current","variants":[
          {"repo":"o/a","engine":"gguf","file":"a.gguf","params":"1B","sizeBytes":1,"vision":{"mmprojFile":"mmproj.gguf"}},
          {"repo":"o/b","engine":"gguf","file":"b.gguf","params":"2B","sizeBytes":1,
           "vision":{"mmprojFile":"mmproj.gguf","mmprojSize":9,"optional":true}}]}
        """.utf8))
        let entries = family.entries(familyIndex: 0)
        #expect(entries[0].capabilities.contains("vision"))
        #expect(!entries[1].capabilities.contains("vision"))
        #expect(entries[1].vision?.isOptional == true)
    }

    // MARK: Download

    @Test func theModelsOwnDownloadLeavesAnOptionalProjectorOutAndTheAddOnFetchesOnlyTheProjector() throws {
        let files = [
            HFFile(path: Self.weights, size: 1_000_000_000, sha256: "aa"),
            HFFile(path: Self.projector, size: 345_911_008, sha256: "bb"), HFFile(path: "README.md", size: 1),
        ]
        #expect(try RepoFiles.downloadPlan(for: modelEntry(), files: files).map(\.path) == [Self.weights])
        #expect(try RepoFiles.downloadPlan(for: modelEntry(optional: false), files: files).map(\.path) == [Self.weights, Self.projector])
        let addOn = try #require(modelEntry().photoAddOn)
        #expect(try RepoFiles.downloadPlan(for: addOn, files: files) == [files[1]], "the listing's checksum rides along")
        #expect(throws: LocalModelError.notFound(Self.projector)) { try RepoFiles.downloadPlan(for: addOn, files: [files[0]]) }
    }

    @Test func theAddOnInstallsOnItsOwnAndLeavesTheModelsManifestAlone() throws {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let entry = modelEntry()
        try install(entry, files: [Self.weights], in: storage)
        let before = try #require(storage.readManifest(entryID: entry.id))
        let addOn = try #require(entry.photoAddOn)
        try install(addOn, files: [Self.projector], in: storage)

        #expect(storage.readManifest(entryID: entry.id) == before, "the engine loads the first file of this manifest")
        #expect(!before.isProjectorOnly)
        #expect(storage.isInstalled(entryID: addOn.id))
        #expect(try #require(storage.readManifest(entryID: addOn.id)).isProjectorOnly)
        #expect(!InstalledManifest(entryID: "x", repo: "o/r", format: .gguf, revision: nil, files: [], completedAt: Date()).isProjectorOnly)

        let record = DownloadJobRecord(entry: addOn, files: [HFFile(path: Self.projector, size: 4)])
        try storage.writeJob(record)
        #expect(storage.pendingJobs() == [record], "an interrupted add-on download is found again at launch")
    }

    // MARK: Which projector is on disk

    @Test func theProjectorIsFoundInTheModelsDownloadOrAsTheAddOnAndOnlyWhileTheFileExists() throws {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let entry = modelEntry()
        try install(entry, files: [Self.weights], in: storage)
        #expect(storage.projectorURL(forEntryID: entry.id, addOn: entry.photoAddOn) == nil, "the model alone is text only")

        let addOn = try #require(entry.photoAddOn)
        try install(addOn, files: [Self.projector], in: storage)
        #expect(storage.projectorURL(forEntryID: entry.id, addOn: addOn) == storage.fileURL(forEntryID: addOn.id, path: Self.projector))
        #expect(storage.projectorURL(forEntryID: entry.id, addOn: nil) == nil, "without the catalog's add-on there is nothing to look for")

        try storage.delete(entryID: addOn.id)
        #expect(storage.projectorURL(forEntryID: entry.id, addOn: addOn) == nil, "removed")

        let bundled = modelEntry(optional: false)
        let other = LocalModelStorage(root: makeTempDirectory())
        try install(bundled, files: [Self.weights, Self.projector], in: other)
        let inModel = other.fileURL(forEntryID: bundled.id, path: Self.projector)
        #expect(other.projectorURL(forEntryID: bundled.id, addOn: nil) == inModel)
        try FileManager.default.removeItem(at: inModel)
        #expect(other.projectorURL(forEntryID: bundled.id, addOn: nil) == nil, "listed in the manifest but gone from disk")
    }

    @Test func anInstalledSizeListsVisionOnlyWhileItsAddOnIsOnDiskAndTheDeviceHasRoom() throws {
        let storage = LocalModelStorage(root: makeTempDirectory())
        let entry = modelEntry()
        try install(entry, files: [Self.weights], in: storage)
        func listed(_ gigabytes: Double) -> [ModelDescriptor] {
            LocalModelDescriptors.installed(format: .gguf, storage: storage, catalog: [entry], memory: memory(gigabytes))
        }
        #expect(listed(8).map(\.id) == [entry.id])
        #expect(listed(8).first?.capabilities.contains("vision") == false, "absent: the model alone reads no photos")

        let addOn = try #require(entry.photoAddOn)
        try install(addOn, files: [Self.projector], in: storage)
        #expect(listed(8).map(\.id) == [entry.id], "the add-on is part of its model, not a model in the list")
        #expect(listed(8).first?.capabilities.contains("vision") == true, "present")
        #expect(listed(1.5).first?.capabilities.contains("vision") == false, "present, but no room for it on this device")

        try storage.delete(entryID: addOn.id)
        #expect(listed(8).first?.capabilities.contains("vision") == false, "removed")
    }
}
