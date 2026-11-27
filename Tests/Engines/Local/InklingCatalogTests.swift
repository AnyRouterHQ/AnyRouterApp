import Foundation
import Testing
@testable import AnyRouter

/// The Inkling 2 Mini catalog entry as the app reads it: the renamed file, the experimental badge, the sampling the
/// publisher recommends and the reply cap. The JSON is the family from catalog/dev-models.json.
struct InklingCatalogTests {
    private static let json = ##"""
    {"schemaVersion": 2, "updatedAt": "2026-11-27", "families": [{
      "id": "inkling-2", "name": "Inkling 2 Mini", "publisher": "Thinking Machines", "line": "inkling",
      "logo": "thinkingmachines", "summary": "S", "website": "https://huggingface.co/thinkingmachines/Inkling-2-Mini",
      "tags": ["thinking"], "badges": ["experimental"], "status": "current", "order": 9,
      "variants": [{
        "repo": "unsloth/Inkling-2-Mini-GGUF", "engine": "gguf",
        "file": "Mainline_Support/Inkling-2-Mini-UD-IQ1_S.gguf_file", "params": "26B", "quant": "IQ1_S",
        "sizeBytes": 7764293056, "contextLength": 1048576, "license": "apache-2.0",
        "revision": "8078d149286eec7193795413b9e0643da6d11fa1",
        "sha256": "17a7ff34acb0e1fe878309962458e0633172c7f93ffe3b1c4f5f6b317dc317db",
        "sampling": {"temperature": 1.0, "topP": 1.0, "topK": 0, "minP": 0.0, "maxOutputTokens": 1024},
        "memory": {"fullKVBytesPerToken": 16384, "windowKVBytesPerToken": 81920, "windowTokens": 1024,
                   "activeFraction": 0.119, "lazyWeightBytes": 246053376}
      }]
    }]}
    """##

    private func entry() throws -> CatalogEntry {
        try #require(try CatalogDocument.decode(Data(Self.json.utf8)).models.first)
    }

    @Test func theEntryKeepsTheRepoPathAndShowsTheDownloadSize() throws {
        let entry = try entry()
        #expect(entry.id == "gguf/unsloth/Inkling-2-Mini-GGUF/Mainline_Support/Inkling-2-Mini-UD-IQ1_S.gguf_file")
        #expect(entry.sizeBytes == 7_764_293_056)
        #expect(entry.title == "Inkling 2 Mini 26B")
        #expect(entry.supportsThinking)
        #expect(entry.vision == nil, "text only until the projector is an optional download")
    }

    @Test func theFamilyBadgeReadsExperimentalAndSlowAsAWarning() throws {
        let entry = try entry()
        #expect(entry.badges == [CatalogBadge(label: "Experimental · slow", tone: "warning")])
    }

    @Test func theSamplingAndTheReplyCapSurviveARoundTrip() throws {
        let entry = try entry()
        let sampling = try #require(entry.sampling)
        #expect(sampling == CatalogSampling(temperature: 1.0, topP: 1.0, topK: 0, minP: 0, maxOutputTokens: 1024))
        let again = try JSONDecoder().decode(CatalogEntry.self, from: try JSONEncoder().encode(entry))
        #expect(again.sampling == sampling)
    }

    @Test func theRenamedFileIsSavedAsGGUFAndOtherFilesKeepTheirNames() throws {
        let entry = try entry()
        let file = try #require(entry.file)
        let storage = LocalModelStorage(root: URL(fileURLWithPath: "/models"))
        #expect(storage.fileURL(forEntryID: entry.id, path: file).path.hasSuffix("/Mainline_Support/Inkling-2-Mini-UD-IQ1_S.gguf"))
        #expect(storage.partialFileURL(forEntryID: entry.id, path: file).lastPathComponent == "Inkling-2-Mini-UD-IQ1_S.gguf")
        #expect(LocalModelStorage.diskPath(forRepoPath: "a/model-Q4_K_M.gguf") == "a/model-Q4_K_M.gguf")
        #expect(LocalModelStorage.diskPath(forRepoPath: "mmproj-F16.gguf") == "mmproj-F16.gguf")
    }

    @Test func aRenamedFileInstallsUnderItsGGUFName() throws {
        let entry = try entry()
        let file = try #require(entry.file)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalModelStorage(root: root)
        let partial = storage.partialFileURL(forEntryID: entry.id, path: file)
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("GGUF".utf8).write(to: partial)
        try ModelInstaller.verifyAndInstall(DownloadJobRecord(entry: entry, files: [HFFile(path: file, size: 4)]), storage: storage)
        let installed = storage.fileURL(forEntryID: entry.id, path: file)
        #expect(installed.pathExtension == "gguf")
        #expect(FileManager.default.fileExists(atPath: installed.path))
        #expect(storage.readManifest(entryID: entry.id)?.files.map(\.path) == [file], "the manifest keeps the repo path")
    }

    @Test func aDownloadLeavesAtLeastOneGigabyteFree() {
        #expect(ModelDownloadManager.spareBytes(forDownload: 7_764_293_056) == 1_000_000_000)
        #expect(ModelDownloadManager.spareBytes(forDownload: 20_000_000_000) == 2_000_000_000)
    }
}

/// The publisher's sampling replaces the app's settings for that model, and the cap only ever shortens a reply.
struct CatalogSamplingTests {
    @Test func setValuesReplaceTheAppDefaults() {
        var params = GenerationParams()
        params.temperature = 0.2
        params.topP = 0.5
        let sampling = CatalogSampling(temperature: 1.0, topP: 1.0)
        let tuned = sampling.applied(to: params)
        #expect(tuned.temperature == 1.0)
        #expect(tuned.topP == 1.0)
        #expect(tuned.maxTokens == nil)
    }

    @Test func missingValuesKeepTheAppSettings() {
        var params = GenerationParams()
        params.temperature = 0.3
        let tuned = CatalogSampling().applied(to: params)
        #expect(tuned.temperature == 0.3)
        #expect(tuned.topP == GenerationParams().topP)
    }

    @Test func theCapAppliesWithNoLimitAndNeverRaisesAShorterOne() {
        let cap = CatalogSampling(maxOutputTokens: 1024)
        #expect(cap.applied(to: GenerationParams()).maxTokens == 1024)
        var short = GenerationParams()
        short.maxTokens = 200
        #expect(cap.applied(to: short).maxTokens == 200)
        var long = GenerationParams()
        long.maxTokens = 4000
        #expect(cap.applied(to: long).maxTokens == 1024)
    }
}
