import Foundation
import Testing
@testable import AnyRouter

/// The storage list shows what is on disk, not what the catalog lists today: a model whose entry was removed must stay
/// visible with its size and deletable, a download that stopped part way must be found, and the launch clean-up must
/// never name a folder that holds an installed model.
struct StorageInventoryLogicTests {
    private typealias Item = StorageInventoryLogic.Item

    private func manifest(_ id: String, repo: String, format: LocalModelFormat = .gguf, file: String = "m.gguf") -> InstalledManifest {
        InstalledManifest(entryID: id, repo: repo, format: format, revision: nil, files: [.init(path: file, size: 1)],
                          completedAt: Date(timeIntervalSince1970: 0))
    }

    private func installed(_ name: String, _ manifest: InstalledManifest, bytes: Int64) -> ModelFolder {
        ModelFolder(name: name, hasManifest: true, manifest: manifest, bytes: bytes)
    }

    private func items(_ folders: [ModelFolder], names: [String: String] = [:], running: Set<String> = []) -> [Item] {
        StorageInventoryLogic.items(folders: folders, names: names, running: running)
    }

    @Test func aModelTheCatalogDroppedStaysListedWithItsSizeAndLoadsAsAnOffCatalogRow() {
        let listed = installed("a", manifest("gguf/org/A-GGUF/a.gguf", repo: "org/A-GGUF"), bytes: 2_000)
        let dropped = installed("q", manifest("gguf/unsloth/Qwen3-0.6B-GGUF/q.gguf", repo: "unsloth/Qwen3-0.6B-GGUF"), bytes: 397_000_000)
        let mlx = installed("m", manifest("mlx/org/M-4bit", repo: "org/M-4bit", format: .mlx, file: "config.json"), bytes: 5)
        let rows = items([listed, dropped, mlx], names: ["gguf/org/A-GGUF/a.gguf": "A"])

        #expect(rows.map(\.name) == ["Qwen3-0.6B-GGUF", "A", "M-4bit"], "biggest first")
        #expect(rows.map(\.kind) == [.offCatalog, .installed, .offCatalog])
        #expect(rows.map(\.source) == [.gguf, .gguf, .mlx])
        #expect(rows[0].folders == ["q"] && rows[0].id == "gguf/unsloth/Qwen3-0.6B-GGUF/q.gguf")

        let entries = StorageInventoryLogic.offCatalogEntries(rows)
        #expect(entries.map(\.id) == ["gguf/unsloth/Qwen3-0.6B-GGUF/q.gguf", "mlx/org/M-4bit"], "only models the catalog dropped")
        #expect(entries.allSatisfy { $0.isOffCatalog && $0.descriptor.isInstalled && $0.summary == "No longer in the catalog" })
        #expect(entries[0].descriptor.sizeBytes == 397_000_000 && entries[0].descriptor.source == .gguf && entries[0].tags == ["gguf"])
        #expect(entries[1].descriptor.source == .mlx && entries[1].tags == ["mlx"])
    }

    @Test func aDownloadThatStoppedPartWayIsUnfinishedUnlessItIsStillRunning() {
        let entry = sampleGGUF(title: "Model")
        let stopped = ModelFolder(name: "p", hasJob: true, job: DownloadJobRecord(entry: entry, files: []), bytes: 412)
        let moving = ModelFolder(name: "r", hasJob: true, job: DownloadJobRecord(entry: sampleGGUF(file: "r.gguf", title: "R"), files: []), bytes: 10)
        let rows = items([stopped, moving], names: [entry.id: "Catalog name"], running: ["r"])

        #expect(rows.map(\.kind) == [.partial, .partial])
        #expect(rows[0].id == entry.id && rows[0].name == "Catalog name" && !rows[0].isRunning)
        #expect(rows[1].name == "R" && rows[1].isRunning, "a removed entry keeps the title its download record saved")
        #expect(StorageInventoryLogic.unfinished(rows).map(\.folders) == [["p"]], "a running download is left alone")
    }

    @Test func filesNoRecordExplainsAreLeftoversNamedByTheirFolder() {
        let empty = ModelFolder(name: "empty")
        let unreadableManifest = ModelFolder(name: "old", hasManifest: true, bytes: 30)
        let unreadableJob = ModelFolder(name: "job", hasJob: true, bytes: 20)
        let rows = items([empty, unreadableManifest, unreadableJob])
        #expect(rows.map(\.id) == ["old", "job", "empty"])
        #expect(rows.allSatisfy { $0.kind == .orphan && $0.source == nil && $0.folders == [$0.id] && $0.name == $0.id })
    }

    @Test func aPhotoAddOnBelongsToItsOnlyModelAndIsALeftoverWhenTheModelIsGone() {
        let parent = installed("v", manifest("gguf/org/V-GGUF/v.gguf", repo: "org/V-GGUF"), bytes: 1_000)
        let addOn = installed("v-proj", manifest("gguf/org/V-GGUF/mmproj-F16.gguf", repo: "org/V-GGUF", file: "mmproj-F16.gguf"), bytes: 200)
        let folded = items([parent, addOn])
        #expect(folded.count == 1 && folded[0].bytes == 1_200 && folded[0].folders == ["v", "v-proj"], "its size and its delete")

        let alone = items([addOn])
        #expect(alone.map(\.kind) == [.orphan] && alone[0].name == "V-GGUF photo support" && alone[0].source == nil)
        #expect(items([addOn], names: ["gguf/org/V-GGUF/mmproj-F16.gguf": "V photo support"])[0].name == "V photo support")

        let sibling = installed("v8", manifest("gguf/org/V-GGUF/v8.gguf", repo: "org/V-GGUF"), bytes: 900)
        let shared = items([parent, sibling, addOn])
        #expect(shared.first { $0.id.hasSuffix("mmproj-F16.gguf") }?.kind == .installed, "two models use it: its own row, never deleted with one of them")
        #expect(shared.allSatisfy { $0.folders.count == 1 })
    }

    @Test func theLineUnderEachRowSaysWhatItIs() {
        func item(_ kind: Item.Kind, running: Bool = false) -> Item {
            Item(id: "x", name: "x", bytes: 1, kind: kind, folders: ["x"], source: nil, isRunning: running)
        }
        #expect(StorageInventoryLogic.note(item(.installed)) == nil)
        #expect(StorageInventoryLogic.note(item(.offCatalog)) == "No longer in the catalog")
        #expect(StorageInventoryLogic.note(item(.partial)) == "Unfinished download")
        #expect(StorageInventoryLogic.note(item(.orphan)) == "Leftover files")
        #expect(StorageInventoryLogic.note(item(.partial, running: true)) == "Downloading")
    }

    @Test func theSummaryAddsEveryRowAndTheFreeSpace() {
        let rows = [
            Item(id: "a", name: "a", bytes: 3_000_000_000, kind: .installed, folders: ["a"], source: .gguf, isRunning: false),
            Item(id: "b", name: "b", bytes: 412_000_000, kind: .partial, folders: ["b"], source: nil, isRunning: false),
        ]
        #expect(StorageInventoryLogic.totalBytes(rows) == 3_412_000_000)
        #expect(StorageInventoryLogic.summary(rows, freeBytes: 21_000_000_000) == "Models use 3.4 GB · 21.0 GB free")
        #expect(StorageInventoryLogic.summary([], freeBytes: nil) == "Models use 0 MB")
        #expect(StorageInventoryLogic.repoName("unsloth/Qwen3-0.6B-GGUF") == "Qwen3-0.6B-GGUF")
        #expect(StorageInventoryLogic.repoName("") == "")
    }

    @Test func theLaunchCleanUpNamesOnlyFoldersWithNoManifestNoRecordAndNoDownload() {
        let folders = [
            installed("model", manifest("gguf/m", repo: "org/m"), bytes: 1),
            ModelFolder(name: "unreadable", hasManifest: true),
            ModelFolder(name: "paused", hasJob: true),
            ModelFolder(name: "partial-left", bytes: 400),
            ModelFolder(name: "empty"),
            ModelFolder(name: "live"),
        ]
        #expect(StorageInventoryLogic.leftovers(folders, running: ["live"]) == ["partial-left", "empty"])
    }
}
