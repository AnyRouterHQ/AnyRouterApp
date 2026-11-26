import Foundation
import Testing
@testable import AnyRouter

struct HuggingFaceAPITests {
    private let api = HuggingFaceAPI(http: FakeHTTP())

    private func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func searchURLFiltersByFormatAndSortsByDownloads() {
        let url = api.searchURL(query: "qwen3 4b", format: .gguf, limit: 10)
        #expect(url.path == "/api/models")
        #expect(url.host == "huggingface.co")
        let q = queryItems(url)
        #expect(q["search"] == "qwen3 4b")
        #expect(q["filter"] == "gguf")
        #expect(q["pipeline_tag"] == "text-generation")
        #expect(q["sort"] == "downloads")
        #expect(q["direction"] == "-1")
        #expect(q["limit"] == "10")
        #expect(queryItems(api.searchURL(query: "x", format: .mlx))["filter"] == "mlx")
    }

    @Test func blankSearchQueryIsOmittedSoTheHubShowsTheMostDownloaded() {
        #expect(queryItems(api.searchURL(query: "  ", format: .mlx))["search"] == nil)
    }

    @Test func treeURLListsRecursivelyAtTheRevision() {
        let url = api.treeURL(repo: "org/name", revision: "abc123")
        #expect(url.path == "/api/models/org/name/tree/abc123")
        #expect(queryItems(url)["recursive"] == "true")
    }

    @Test func resolveURLKeepsSlashesAndEncodesSpaces() {
        let url = api.resolveURL(repo: "org/name", revision: "main", path: "sub dir/model (1).gguf")
        #expect(url.absoluteString == "https://huggingface.co/org/name/resolve/main/sub%20dir/model%20(1).gguf")
    }

    @Test(arguments: ["org/name", "Qwen/Qwen3-4B-GGUF", "a1/b.c_d-e"])
    func acceptsRealRepoIDs(_ repo: String) {
        #expect(HuggingFaceAPI.isValidRepo(repo))
    }

    @Test(arguments: ["", "name", "org/", "/name", "org/na me", "org/../x", "../org/x", "org/name/extra", "org/na?me", "-org/name"])
    func rejectsMalformedRepoIDs(_ repo: String) {
        #expect(!HuggingFaceAPI.isValidRepo(repo))
    }

    @Test(arguments: ["../x", "a/../x", "/abs", "a//b", "", "./a", "a\\b"])
    func rejectsUnsafeFilePaths(_ path: String) {
        #expect(!HuggingFaceAPI.isSafeFilePath(path))
    }

    @Test func acceptsNestedRelativeFilePaths() {
        #expect(HuggingFaceAPI.isSafeFilePath("model.gguf"))
        #expect(HuggingFaceAPI.isSafeFilePath("sub/model-00001.safetensors"))
    }

    @Test func decodeTreeKeepsFilesOnlyAndReadsLFSChecksum() throws {
        let json = """
        [
          {"type":"directory","path":"onnx","oid":"d"},
          {"type":"file","path":"config.json","size":937,"oid":"c"},
          {"type":"file","path":"model.safetensors","size":335450584,"oid":"x","lfs":{"oid":"ABC123","size":335450584,"pointerSize":134}}
        ]
        """
        let files = try HuggingFaceAPI.decodeTree(Data(json.utf8))
        #expect(files == [
            HFFile(path: "config.json", size: 937, sha256: nil),
            HFFile(path: "model.safetensors", size: 335_450_584, sha256: "ABC123"),
        ])
    }

    @Test func decodeTreeRefusesPathsThatEscapeTheModelFolder() {
        let json = #"[{"type":"file","path":"../../evil","size":1}]"#
        #expect(throws: LocalModelError.invalidFilePath("../../evil")) {
            try HuggingFaceAPI.decodeTree(Data(json.utf8))
        }
    }

    @Test func searchDecodesResultsAndDropsBadRepoIDs() async throws {
        let json = """
        [{"id":"unsloth/Qwen3-4B-GGUF","downloads":10,"likes":2,"pipeline_tag":"text-generation","tags":["gguf"]},
         {"id":"weird id","downloads":1}]
        """
        let api = HuggingFaceAPI(http: FakeHTTP(body: json))
        let results = try await api.search(query: "qwen", format: .gguf)
        #expect(results.map(\.id) == ["unsloth/Qwen3-4B-GGUF"])
        #expect(results.first?.downloads == 10)
        #expect(results.first?.pipelineTag == "text-generation")
    }

    @Test func listFilesSendsTheRequestedRevision() async throws {
        let seen = LockedBox<String?>(nil)
        let api = HuggingFaceAPI(http: FakeHTTP { request in
            seen.value = request.url?.path
            return (Data("[]".utf8), 200)
        })
        _ = try await api.listFiles(repo: "org/name", revision: "deadbeef")
        #expect(seen.value == "/api/models/org/name/tree/deadbeef")
    }

    @Test func listFilesRefusesAnInvalidRepoBeforeAnyRequest() async {
        let api = HuggingFaceAPI(http: FakeHTTP { _ in
            Issue.record("no request expected")
            return (Data(), 200)
        })
        await #expect(throws: LocalModelError.invalidRepo("../x")) { try await api.listFiles(repo: "../x") }
    }

    @Test func httpStatusesMapToSpecificErrors() async {
        func listing(_ status: Int) -> HuggingFaceAPI { HuggingFaceAPI(http: FakeHTTP(status: status)) }
        await #expect(throws: LocalModelError.notFound("org/name")) { try await listing(404).listFiles(repo: "org/name") }
        await #expect(throws: LocalModelError.gatedOrPrivate("org/name")) { try await listing(401).listFiles(repo: "org/name") }
        await #expect(throws: LocalModelError.gatedOrPrivate("org/name")) { try await listing(403).listFiles(repo: "org/name") }
        await #expect(throws: LocalModelError.http(status: 503)) { try await listing(503).listFiles(repo: "org/name") }
    }
}

/// Lets a Sendable fake record what it saw.
final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}


struct PrefixFetchTests {
    @Test func theSessionReturnsOnlyTheRequestedPrefixAndAsksForARange() async throws {
        let seen = StubSeen()
        let stub = StubbedAPI { request in
            seen.set(request.value(forHTTPHeaderField: "Range"))
            return .init(status: 206, body: Data(repeating: 7, count: 10_000))
        }
        let (data, response) = try await stub.session.fetchPrefix(URLRequest(url: URL(string: "https://\(stub.host)/f")!), maxBytes: 100)
        #expect(data.count == 100 && response.statusCode == 206)
        #expect(seen.value == "bytes=0-99")
    }

    @Test func aServerThatIgnoresTheRangeAndKeepsStreamingIsCutOffAtTheLimit() async throws {
        let stub = StubbedAPI { _ in .init(status: 200, body: Data(repeating: 1, count: 5_000), hangs: true) }
        let (data, _) = try await stub.session.fetchPrefix(URLRequest(url: URL(string: "https://\(stub.host)/f")!), maxBytes: 1_000)
        #expect(data.count == 1_000, "it must not wait for the end of a body that never ends")
        for _ in 0..<50 where !StubRegistry.shared.wasStopped(host: stub.host) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(StubRegistry.shared.wasStopped(host: stub.host), "the transfer is cancelled, not left running")
    }

    @Test func aBodyShorterThanTheLimitIsReturnedWhole() async throws {
        let stub = StubbedAPI { _ in .init(status: 200, body: Data(repeating: 2, count: 40)) }
        let (data, _) = try await stub.session.fetchPrefix(URLRequest(url: URL(string: "https://\(stub.host)/f")!), maxBytes: 1_000)
        #expect(data.count == 40)
    }

    @Test func aResponseThatIsNotHTTPIsAnError() async {
        let stub = StubbedAPI { _ in .init(nonHTTP: true) }
        await #expect(throws: LocalModelError.invalidResponse) {
            _ = try await stub.session.fetchPrefix(URLRequest(url: URL(string: "https://\(stub.host)/f")!), maxBytes: 10)
        }
    }

    @Test func headerReadsMapHTTPStatusesToTheSameErrorsAsListings() async {
        for (status, expected) in [(403, LocalModelError.gatedOrPrivate("org/m")), (404, .notFound("org/m")), (500, .http(status: 500))] {
            let api = HuggingFaceAPI(http: FakeHTTP(status: status))
            await #expect(throws: expected) { _ = try await api.ggufInfo(repo: "org/m", file: "m.gguf") }
        }
        await #expect(throws: LocalModelError.invalidRepo("nope")) { _ = try await HuggingFaceAPI().ggufInfo(repo: "nope", file: "m.gguf") }
    }
}

private final class StubSeen: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    func set(_ value: String?) { lock.withLock { stored = value } }
    var value: String? { lock.withLock { stored } }
}
