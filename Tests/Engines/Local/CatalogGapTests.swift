import Foundation
import Testing
@testable import AnyRouter

struct LocalModelErrorTests {
    @Test func everyErrorTellsTheUserWhatToDo() {
        let cases: [(LocalModelError, String)] = [
            (.invalidRepo("x"), "Not a Hugging Face repo id: x"),
            (.invalidFilePath("../a"), "Unsafe file path in repo listing: ../a"),
            (.invalidResponse, "Unexpected response from Hugging Face."),
            (.http(status: 503), "Hugging Face answered HTTP 503."),
            (.notFound("org/m"), "Not found on Hugging Face: org/m"),
            (.gatedOrPrivate("org/m"), "org/m is gated or private. Accept its terms on huggingface.co first."),
            (.noFiles("org/m"), "No downloadable model files in org/m."),
            (.insufficientSpace(neededBytes: 5_000_000_000, freeBytes: 1_000_000_000), "Not enough free space: needs 5000 MB, 1000 MB free."),
            (.checksumMismatch("a.gguf"), "Checksum mismatch for a.gguf. Download it again."),
            (.sizeMismatch("a.gguf"), "Size mismatch for a.gguf. Download it again."),
            (.unsupportedCatalogVersion(9), "Catalog schema version 9 is not supported by this app."),
        ]
        for (error, text) in cases { #expect(error.errorDescription == text) }
    }
}

struct BundledCatalogTests {
    @Test func missingCatalogFileIsALoudError() {
        let empty = Bundle(path: makeTempDirectory().path)
        #expect(throws: (any Error).self) { try BundledCatalog.load(bundle: empty) }
    }

    @Test func theShippedCatalogLoadsAndHasModels() throws {
        #expect(!(try BundledCatalog.load().models.isEmpty))
    }
}

struct CatalogDecodingTests {
    @Test func originsSortUserOverRemoteOverBundled() {
        #expect(CatalogOrigin.bundled < .remote)
        #expect(CatalogOrigin.remote < .user)
        #expect(!(CatalogOrigin.user < .bundled))
    }

    @Test func entryWithAnUnsafeRepoIsRejected() {
        let json = #"{"repo":"../evil","format":"mlx","title":"x"}"#
        #expect(throws: LocalModelError.invalidRepo("../evil")) {
            try JSONDecoder().decode(CatalogEntry.self, from: Data(json.utf8))
        }
    }

    @Test func ggufEntryNeedsASafeFile() {
        let missing = #"{"repo":"org/m","format":"gguf","title":"x"}"#
        let unsafe = #"{"repo":"org/m","format":"gguf","title":"x","file":"../a.gguf"}"#
        #expect(throws: LocalModelError.invalidFilePath("(missing)")) {
            try JSONDecoder().decode(CatalogEntry.self, from: Data(missing.utf8))
        }
        #expect(throws: LocalModelError.invalidFilePath("../a.gguf")) {
            try JSONDecoder().decode(CatalogEntry.self, from: Data(unsafe.utf8))
        }
    }

    @Test func fullEntryRoundTripsThroughJSON() throws {
        let entry = CatalogEntry(
            repo: "org/m", format: .gguf, file: "m-Q4_K_M.gguf", title: "M", summary: "s", parameters: "1B",
            quantization: "Q4_K_M", sizeBytes: 10, contextLength: 4096, license: "apache-2.0", revision: "abc",
            capabilities: ["chat", "tools"], order: 3)
        let back = try JSONDecoder().decode(CatalogEntry.self, from: JSONEncoder().encode(entry))
        #expect(back == entry)
    }

    @Test func entryWithoutCapabilitiesDefaultsToChat() throws {
        let json = #"{"repo":"org/m","format":"mlx","title":"x"}"#
        #expect(try JSONDecoder().decode(CatalogEntry.self, from: Data(json.utf8)).capabilities == ["chat"])
    }

    @Test func newerSchemaReportsItsVersion() {
        #expect(throws: LocalModelError.unsupportedCatalogVersion(3)) {
            try CatalogDocument.decode(Data(#"{"schemaVersion":3,"families":[{"unknown":true}]}"#.utf8))
        }
    }
}

/// Answers from a closure, remembers every request and can send response headers.
final class RecordingHTTP: HTTPFetching, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var body = ""
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var seen: [URLRequest] = []
    private let reply: @Sendable (URLRequest) -> Reply

    init(_ reply: @escaping @Sendable (URLRequest) -> Reply) { self.reply = reply }

    var requests: [URLRequest] { lock.withLock { seen } }

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { seen.append(request) }
        let r = reply(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: nil, headerFields: r.headers)!
        return (Data(r.body.utf8), response)
    }
}

struct CatalogServiceRemoteTests {
    private let remoteURL = URL(string: "https://catalog.test/models.json")!
    private let remoteDoc = #"{"schemaVersion":2,"families":[{"id":"remote","name":"Remote","publisher":"P","variants":[{"repo":"org/remote","engine":"mlx","params":"1B","sizeBytes":1}]}]}"#

    private func service(
        http: any HTTPFetching, settings: CatalogSettings = CatalogSettings(), dir: URL = makeTempDirectory()
    ) -> CatalogService {
        let bundled = CatalogDocument(schemaVersion: 2, updatedAt: nil, models: [sampleMLX(repo: "org/bundled")])
        return CatalogService(
            bundled: { bundled }, api: HuggingFaceAPI(http: http), cacheDirectory: dir, settings: { settings })
    }

    private func custom(_ url: URL? = nil, user: [CatalogEntry] = [], dev: Bool = false) -> CatalogSettings {
        CatalogSettings(userModels: user, remoteCatalogURL: url ?? URL(string: "https://catalog.test/models.json"), useDevelopmentCatalog: dev)
    }

    @Test func withoutAnythingCachedOnlyTheBundledCatalogShows() async throws {
        let s = service(http: FakeHTTP())
        #expect(try await s.entries().map(\.repo) == ["org/bundled"])
    }

    @Test func theSharedCatalogIsFetchedWhenTheUserSetNoURL() async throws {
        let http = RecordingHTTP { _ in .init(body: remoteDoc) }
        let s = service(http: http)
        #expect(try await s.refreshRemote())
        #expect(http.requests.first?.url == CatalogSource.productionURL)
        #expect(try await s.entries().map(\.repo).contains("org/remote"))
    }

    @Test func theDevelopmentSwitchPicksTheDevelopmentCatalog() async throws {
        let http = RecordingHTTP { _ in .init(body: remoteDoc) }
        let s = service(http: http, settings: CatalogSettings(useDevelopmentCatalog: true))
        _ = try await s.refreshRemote()
        #expect(http.requests.first?.url == CatalogSource.developmentURL)
    }

    @Test func refreshedRemoteModelsShowUpMergedWithBundledAndUserOnes() async throws {
        let user = sampleMLX(repo: "org/mine")
        let s = service(http: FakeHTTP(body: remoteDoc), settings: custom(user: [user]))
        #expect(try await s.refreshRemote())
        let entries = try await s.entries()
        #expect(Set(entries.map(\.repo)) == ["org/bundled", "org/remote", "org/mine"])
        #expect(entries.first { $0.repo == "org/remote" }?.origin == .remote)
    }

    @Test func plainHTTPRemoteCatalogIsRefused() async {
        let s = service(http: FakeHTTP(body: remoteDoc), settings: custom(URL(string: "http://catalog.test/models.json")))
        await #expect(throws: URLError.self) { try await s.refreshRemote() }
    }

    @Test func anUnchangedCatalogCostsOneNotModifiedAnswerAndKeepsTheCache() async throws {
        let dir = makeTempDirectory()
        let first = RecordingHTTP { _ in .init(body: remoteDoc, headers: ["ETag": "\"v1\""]) }
        _ = try await service(http: first, settings: custom(), dir: dir).refreshRemote()

        let second = RecordingHTTP { _ in .init(status: 304) }
        let s = service(http: second, settings: custom(), dir: dir)
        #expect(try await s.refreshRemote() == false)
        #expect(second.requests.first?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(try await s.entries().map(\.repo).contains("org/remote"))
    }

    @Test func aCatalogWithoutAnETagForgetsTheOldOne() async throws {
        let dir = makeTempDirectory()
        _ = try await service(http: RecordingHTTP { _ in .init(body: remoteDoc, headers: ["ETag": "\"v1\""]) },
                              settings: custom(), dir: dir).refreshRemote()
        _ = try await service(http: RecordingHTTP { _ in .init(body: remoteDoc) }, settings: custom(), dir: dir).refreshRemote()
        let third = RecordingHTTP { _ in .init(body: remoteDoc) }
        _ = try await service(http: third, settings: custom(), dir: dir).refreshRemote()
        #expect(third.requests.first?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func serverErrorKeepsTheOldCache() async throws {
        let dir = makeTempDirectory()
        _ = try await service(http: FakeHTTP(body: remoteDoc), settings: custom(), dir: dir).refreshRemote()
        let bad = service(http: FakeHTTP(status: 500), settings: custom(), dir: dir)
        await #expect(throws: LocalModelError.http(status: 500)) { try await bad.refreshRemote() }
        #expect(try await bad.entries().map(\.repo).contains("org/remote"))
    }

    @Test func garbageResponseNeverReplacesAGoodCache() async throws {
        let dir = makeTempDirectory()
        _ = try await service(http: FakeHTTP(body: remoteDoc), settings: custom(), dir: dir).refreshRemote()
        let garbage = service(http: FakeHTTP(body: "<html>"), settings: custom(), dir: dir)
        await #expect(throws: (any Error).self) { try await garbage.refreshRemote() }
        #expect(try await garbage.entries().map(\.repo).contains("org/remote"))
    }

    @Test func brokenCacheFileIsIgnored() async throws {
        let dir = makeTempDirectory()
        let s = service(http: FakeHTTP(), settings: custom(), dir: dir)
        let file = await s.cacheFile(for: remoteURL)
        try Data("nope".utf8).write(to: file)
        #expect(try await s.entries().map(\.repo) == ["org/bundled"])
    }

    @Test func eachRemoteURLHasItsOwnCacheFile() async {
        let s = service(http: FakeHTTP())
        let a = await s.cacheFile(for: URL(string: "https://a.test/c.json")!)
        let b = await s.cacheFile(for: URL(string: "https://b.test/c.json")!)
        #expect(a != b)
    }

    @Test func searchAndAddRepoGoThroughHuggingFace() async throws {
        let http = FakeHTTP { request in
            let path = request.url?.path ?? ""
            if path == "/api/models" { return (Data(#"[{"id":"org/found"},{"id":"bad id"}]"#.utf8), 200) }
            return (Data(#"[{"type":"file","path":"model.safetensors","size":4},{"type":"file","path":"config.json","size":2}]"#.utf8), 200)
        }
        let s = service(http: http)
        #expect(try await s.search(query: "q", format: .mlx).map(\.id) == ["org/found"])
        let entries = try await s.entries(forRepo: "org/found", format: .mlx)
        #expect(entries.map(\.id) == ["mlx/org/found"])
        #expect(entries.first?.sizeBytes == 6)
    }

    @Test func aGGUFRepoWhoseHeaderCannotBeReadStillListsItsFiles() async throws {
        let http = FakeHTTP { request in
            if request.url?.path.contains("/tree/") == true {
                return (Data(#"[{"type":"file","path":"m-Q4_K_M.gguf","size":4000},{"type":"file","path":"m-Q8_0.gguf","size":8000}]"#.utf8), 200)
            }
            return (Data("not a gguf".utf8), 200)
        }
        let entries = try await service(http: http).entries(forRepo: "org/m-GGUF", format: .gguf)
        #expect(entries.map(\.file) == ["m-Q4_K_M.gguf", "m-Q8_0.gguf"])
    }
}

struct HuggingFaceAPIErrorTests {
    private func api(_ status: Int, body: String = "[]") -> HuggingFaceAPI {
        HuggingFaceAPI(http: FakeHTTP(status: status, body: body))
    }

    @Test func httpStatusesMapToUsefulErrors() async {
        await #expect(throws: LocalModelError.gatedOrPrivate("org/m")) { try await api(401).listFiles(repo: "org/m") }
        await #expect(throws: LocalModelError.gatedOrPrivate("org/m")) { try await api(403).listFiles(repo: "org/m") }
        await #expect(throws: LocalModelError.notFound("org/m")) { try await api(404).listFiles(repo: "org/m") }
        await #expect(throws: LocalModelError.http(status: 500)) { try await api(500).listFiles(repo: "org/m") }
    }

    @Test func invalidRepoNeverReachesTheNetwork() async {
        let called = Flag()
        let http = FakeHTTP { _ in called.value = true; return (Data("[]".utf8), 200) }
        await #expect(throws: LocalModelError.invalidRepo("../x")) {
            try await HuggingFaceAPI(http: http).listFiles(repo: "../x")
        }
        #expect(!called.value)
    }

    @Test func listingWithAnUnsafePathIsRejected() {
        let body = #"[{"type":"file","path":"../../etc/passwd","size":1}]"#
        #expect(throws: LocalModelError.invalidFilePath("../../etc/passwd")) { try HuggingFaceAPI.decodeTree(Data(body.utf8)) }
    }

    @Test func listingDropsDirectoriesAndKeepsLFSChecksums() throws {
        let body = #"[{"type":"directory","path":"sub"},{"type":"file","path":"sub/a.gguf","size":9,"lfs":{"oid":"abc"}},{"type":"file","path":"README.md"}]"#
        let files = try HuggingFaceAPI.decodeTree(Data(body.utf8))
        #expect(files == [HFFile(path: "sub/a.gguf", size: 9, sha256: "abc"), HFFile(path: "README.md", size: 0, sha256: nil)])
    }

    @Test func searchWithoutQueryOmitsTheSearchParameter() {
        let url = HuggingFaceAPI().searchURL(query: "  ", format: .gguf)
        #expect(!(url.query ?? "").contains("search="))
    }

    @Test func urlSessionFetchReturnsBodyAndStatusAndRejectsNonHTTP() async throws {
        let ok = StubbedAPI { _ in StubRegistry.Reply(status: 201, body: Data("hi".utf8)) }
        let (data, response) = try await ok.session.fetch(URLRequest(url: URL(string: "https://\(ok.host)/x")!))
        #expect(String(decoding: data, as: UTF8.self) == "hi")
        #expect(response.statusCode == 201)

        let odd = StubbedAPI { _ in StubRegistry.Reply(nonHTTP: true) }
        await #expect(throws: LocalModelError.invalidResponse) {
            _ = try await odd.session.fetch(URLRequest(url: URL(string: "https://\(odd.host)/x")!))
        }
    }
}

struct RepoFilesGapTests {
    private func file(_ path: String, _ size: Int64 = 1) -> HFFile { HFFile(path: path, size: size) }

    @Test func ggufEntryWhoseFileIsMissingFromTheRepoIsNotFound() {
        let entry = sampleGGUF(file: "gone.gguf")
        #expect(throws: LocalModelError.notFound("gone.gguf")) { try RepoFiles.downloadPlan(for: entry, files: [file("other.gguf")]) }
    }

    @Test func mlxRepoWithoutWeightsHasNoFiles() {
        #expect(throws: LocalModelError.noFiles("org/model-4bit")) {
            try RepoFiles.downloadPlan(for: sampleMLX(), files: [file("config.json")])
        }
        #expect(throws: LocalModelError.noFiles("org/model-4bit")) {
            try RepoFiles.entries(repo: "org/model-4bit", format: .mlx, files: [file("config.json")])
        }
    }

    @Test func addingARepoValidatesItsNameAndContent() {
        #expect(throws: LocalModelError.invalidRepo("bad")) { try RepoFiles.entries(repo: "bad", format: .gguf, files: []) }
        #expect(throws: LocalModelError.noFiles("org/m")) {
            try RepoFiles.entries(repo: "org/m", format: .gguf, files: [file("mmproj-F16.gguf"), file("README.md")])
        }
    }

    @Test func smallestFileWinsWhenNoPreferredQuantizationFits() {
        let choices = [
            GGUFChoice(path: "a-F16.gguf", sizeBytes: 9_000_000_000, quantization: "F16"),
            GGUFChoice(path: "b-F32.gguf", sizeBytes: 20_000_000_000, quantization: "F32"),
        ]
        #expect(RepoFiles.defaultChoice(choices, fit: DeviceFit(physicalMemory: 8_000_000_000))?.path == "a-F16.gguf")
        #expect(RepoFiles.defaultChoice([]) == nil)
    }

    @Test func preferredQuantizationTooLargeForTheDeviceIsSkipped() {
        let choices = [
            GGUFChoice(path: "m-Q4_K_M.gguf", sizeBytes: 9_000_000_000, quantization: "Q4_K_M"),
            GGUFChoice(path: "m-Q3_K_M.gguf", sizeBytes: 1_000_000_000, quantization: "Q3_K_M"),
        ]
        #expect(RepoFiles.defaultChoice(choices, fit: DeviceFit(physicalMemory: 6_000_000_000))?.path == "m-Q3_K_M.gguf")
    }
}

struct StorageGapTests {
    private func makeStorage() -> LocalModelStorage {
        LocalModelStorage(root: makeTempDirectory().appending(path: "Models", directoryHint: .isDirectory))
    }

    @Test func defaultRootIsTheModelsFolder() {
        #expect(LocalModelStorage().root.lastPathComponent == "Models")
    }

    @Test func freeSpaceIsReportedWithAndWithoutTheRootFolder() throws {
        let storage = makeStorage()
        #expect((storage.freeSpaceBytes() ?? 0) > 0)
        try storage.prepareRoot()
        #expect((storage.freeSpaceBytes() ?? 0) > 0)
    }

    @Test func corruptManifestsAndJobsAreSkipped() throws {
        let storage = makeStorage()
        let entry = sampleMLX()
        try FileManager.default.createDirectory(at: storage.directory(forEntryID: entry.id), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: storage.manifestURL(forEntryID: entry.id))
        try Data("garbage".utf8).write(to: storage.directory(forEntryID: entry.id).appending(path: ".job.json"))
        #expect(storage.readManifest(entryID: entry.id) == nil)
        #expect(storage.installedManifests().isEmpty)
        #expect(storage.pendingJobs().isEmpty)
        #expect(storage.readManifest(entryID: "mlx/missing/model") == nil)
    }

    @Test func installingOverAnExistingFileReplacesIt() throws {
        let storage = makeStorage()
        let entry = sampleMLX()
        for text in ["old!", "new!"] {
            let url = storage.partialFileURL(forEntryID: entry.id, path: "config.json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            let record = DownloadJobRecord(entry: entry, files: [HFFile(path: "config.json", size: 4)])
            try ModelInstaller.verifyAndInstall(record, storage: storage)
        }
        let final = storage.fileURL(forEntryID: entry.id, path: "config.json")
        #expect(try String(contentsOf: final, encoding: .utf8) == "new!")
    }
}
