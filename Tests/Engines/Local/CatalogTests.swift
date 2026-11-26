import Foundation
import Testing
@testable import AnyRouter

struct CatalogTests {
    @Test func bundledCatalogDecodesAndOffersBothFormats() throws {
        let doc = try BundledCatalog.load()
        #expect(doc.schemaVersion == CatalogDocument.supportedSchemaVersion)
        #expect(doc.models.contains { $0.format == .gguf })
        #expect(doc.models.contains { $0.format == .mlx })
        #expect(Set(doc.models.map(\.id)).count == doc.models.count, "ids must be unique")
        for model in doc.models {
            #expect(HuggingFaceAPI.isValidRepo(model.repo))
            #expect((model.sizeBytes ?? 0) > 0, "\(model.id) needs a size for the fit check")
            #expect(model.revision != nil, "\(model.id) should pin a revision")
            if model.format == .gguf { #expect(model.file?.hasSuffix(".gguf") == true) }
        }
    }

    @Test func gemma4OffersBothSizesInBothFormatsAtAPinnedRevision() throws {
        let doc = try BundledCatalog.load()
        let gemma4 = doc.models.filter { $0.title.hasPrefix("Gemma 4") }
        #expect(Set(gemma4.map { "\($0.parameters ?? "")/\($0.format.rawValue)" }) == ["E2B/gguf", "E2B/mlx", "E4B/gguf", "E4B/mlx"])
        for model in gemma4 {
            #expect(model.revision?.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil, "\(model.id) needs a commit sha, not a branch")
            #expect(model.contextLength == 131_072)
            #expect(model.license == "apache-2.0")
            #expect(model.summary?.contains("RAM") == true, "\(model.id) needs a device-fit hint")
        }
        // The bigger model must never look smaller than the E2B one in the same format.
        for format in LocalModelFormat.allCases {
            let e2b = try #require(gemma4.first { $0.parameters == "E2B" && $0.format == format }?.sizeBytes)
            let e4b = try #require(gemma4.first { $0.parameters == "E4B" && $0.format == format }?.sizeBytes)
            #expect(e4b > e2b)
        }
    }

    @Test func entryIDsFollowTheDescriptorContract() {
        #expect(sampleGGUF(repo: "org/m", file: "m-Q4_K_M.gguf").id == "gguf/org/m/m-Q4_K_M.gguf")
        #expect(sampleMLX(repo: "org/m-4bit").id == "mlx/org/m-4bit")
    }

    @Test func decodeRejectsANewerSchemaWithItsVersion() {
        let json = #"{"schemaVersion": 99, "models": [{"unknown": true}]}"#
        #expect(throws: LocalModelError.unsupportedCatalogVersion(99)) {
            try CatalogDocument.decode(Data(json.utf8))
        }
    }

    @Test func decodeRejectsUnsafeRepoAndMissingGGUFFile() {
        let badRepo = #"{"schemaVersion":1,"models":[{"repo":"../etc/passwd","format":"mlx","title":"x"}]}"#
        #expect(throws: LocalModelError.invalidRepo("../etc/passwd")) {
            try CatalogDocument.decode(Data(badRepo.utf8))
        }
        let noFile = #"{"schemaVersion":1,"models":[{"repo":"org/m","format":"gguf","title":"x"}]}"#
        #expect(throws: LocalModelError.invalidFilePath("(missing)")) {
            try CatalogDocument.decode(Data(noFile.utf8))
        }
        let traversal = #"{"schemaVersion":1,"models":[{"repo":"org/m","format":"gguf","file":"../x.gguf","title":"x"}]}"#
        #expect(throws: LocalModelError.invalidFilePath("../x.gguf")) {
            try CatalogDocument.decode(Data(traversal.utf8))
        }
    }

    @Test func minimalEntryGetsChatCapabilityAndRoundTrips() throws {
        let json = #"{"schemaVersion":1,"models":[{"repo":"org/m","format":"mlx","title":"M"}]}"#
        let entry = try #require(try CatalogDocument.decode(Data(json.utf8)).models.first)
        #expect(entry.capabilities == ["chat"])
        let back = try JSONDecoder().decode(CatalogEntry.self, from: JSONEncoder().encode(entry))
        #expect(back == entry)
    }

    @Test func originIsNotWrittenToJSON() throws {
        var entry = sampleMLX()
        entry.origin = .user
        let text = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        #expect(!text.contains("origin"))
    }
}

struct CatalogMergeTests {
    @Test func userBeatsRemoteBeatsBundledForTheSameID() {
        let bundled = sampleMLX(title: "bundled")
        let remote = sampleMLX(title: "remote")
        let user = sampleMLX(title: "user")
        #expect(CatalogMerger.merge(bundled: [bundled], remote: [remote], user: [user]).map(\.title) == ["user"])
        #expect(CatalogMerger.merge(bundled: [bundled], remote: [remote]).map(\.title) == ["remote"])
        #expect(CatalogMerger.merge(bundled: [bundled], remote: [remote]).first?.origin == .remote)
    }

    @Test func originFollowsTheSourceListNotTheEntry() {
        var claimsUser = sampleMLX(repo: "org/a")
        claimsUser.origin = .user
        let merged = CatalogMerger.merge(bundled: [claimsUser])
        #expect(merged.first?.origin == .bundled)
    }

    @Test func sortsByOrderThenTitleThenIDAndNilOrderComesLast() {
        let entries = [
            sampleMLX(repo: "org/z", order: nil, title: "Alpha"),
            sampleMLX(repo: "org/b", order: 2, title: "Beta"),
            sampleMLX(repo: "org/a2", order: 1, title: "beta"),
            sampleMLX(repo: "org/a1", order: 1, title: "Beta"),
            sampleMLX(repo: "org/c", order: 1, title: "Aardvark"),
        ]
        #expect(CatalogMerger.merge(bundled: entries).map(\.repo) == ["org/c", "org/a1", "org/a2", "org/b", "org/z"])
    }

    @Test func resultDoesNotDependOnInputOrder() {
        let entries = (0..<20).map { sampleMLX(repo: "org/m\($0)", order: $0 % 4, title: "T\($0 % 3)") }
        let expected = CatalogMerger.merge(bundled: entries).map(\.id)
        for _ in 0..<10 {
            #expect(CatalogMerger.merge(bundled: entries.shuffled()).map(\.id) == expected)
        }
    }
}

struct CatalogSettingsTests {
    @Test func roundTripsThroughUserDefaults() throws {
        let defaults = UserDefaults(suiteName: "anyrouter-tests-\(UUID().uuidString)")!
        var settings = CatalogSettings()
        settings.add([sampleGGUF()])
        settings.remoteCatalogURL = URL(string: "https://example.org/catalog.json")
        try settings.save(to: defaults)
        #expect(CatalogSettings.load(from: defaults) == settings)
    }

    @Test func emptyDefaultsGiveEmptySettings() {
        let defaults = UserDefaults(suiteName: "anyrouter-tests-\(UUID().uuidString)")!
        #expect(CatalogSettings.load(from: defaults) == CatalogSettings())
    }

    @Test func addReplacesSameIDAndRemoveDrops() {
        var settings = CatalogSettings()
        settings.add([sampleGGUF(title: "one")])
        settings.add([sampleGGUF(title: "two")])
        #expect(settings.userModels.map(\.title) == ["two"])
        settings.remove(id: sampleGGUF().id)
        #expect(settings.userModels.isEmpty)
    }

    @Test func onlyHTTPSRemoteCatalogsAreAccepted() {
        #expect(CatalogSettings.isAcceptableRemoteCatalogURL(URL(string: "https://example.org/c.json")!))
        #expect(!CatalogSettings.isAcceptableRemoteCatalogURL(URL(string: "http://example.org/c.json")!))
        #expect(!CatalogSettings.isAcceptableRemoteCatalogURL(URL(string: "file:///tmp/c.json")!))
    }
}

struct CatalogServiceTests {
    private func document(_ models: [CatalogEntry]) -> CatalogDocument {
        CatalogDocument(schemaVersion: 1, updatedAt: nil, models: models)
    }

    private func remoteJSON(title: String) -> String {
        #"{"schemaVersion":1,"models":[{"repo":"org/remote","format":"mlx","title":"\#(title)"}]}"#
    }

    @Test func entriesMergeBundledAndUserModels() async throws {
        let bundled = document([sampleMLX(repo: "org/bundled", order: 0)])
        let user = sampleGGUF(repo: "org/mine", order: 1)
        let service = CatalogService(
            bundled: { bundled }, cacheDirectory: makeTempDirectory(),
            settings: { CatalogSettings(userModels: [user]) })
        let entries = try await service.entries()
        #expect(entries.map(\.repo) == ["org/bundled", "org/mine"])
        #expect(entries.last?.origin == .user)
    }

    @Test func refreshCachesRemoteAndEntriesUseIt() async throws {
        let cache = makeTempDirectory()
        let url = URL(string: "https://example.org/catalog.json")!
        let settings = CatalogSettings(remoteCatalogURL: url)
        let service = CatalogService(
            bundled: { CatalogDocument(schemaVersion: 1, updatedAt: nil, models: []) },
            api: HuggingFaceAPI(http: FakeHTTP(body: remoteJSON(title: "R"))),
            cacheDirectory: cache, settings: { settings })
        #expect(try await service.entries().isEmpty)
        #expect(try await service.refreshRemote())
        let entries = try await service.entries()
        #expect(entries.map(\.title) == ["R"])
        #expect(entries.first?.origin == .remote)
    }

    @Test func clearingTheRemoteURLStopsUsingTheCachedCopy() async throws {
        let cache = makeTempDirectory()
        let url = URL(string: "https://example.org/catalog.json")!
        let withURL = CatalogSettings(remoteCatalogURL: url)
        let first = CatalogService(
            bundled: { CatalogDocument(schemaVersion: 1, updatedAt: nil, models: []) },
            api: HuggingFaceAPI(http: FakeHTTP(body: remoteJSON(title: "R"))),
            cacheDirectory: cache, settings: { withURL })
        try await first.refreshRemote()
        let second = CatalogService(
            bundled: { CatalogDocument(schemaVersion: 1, updatedAt: nil, models: []) },
            cacheDirectory: cache, settings: { CatalogSettings() })
        #expect(try await second.entries().isEmpty)
    }

    @Test func aBadRemoteResponseNeverReplacesAGoodCache() async throws {
        let cache = makeTempDirectory()
        let url = URL(string: "https://example.org/catalog.json")!
        let settings = CatalogSettings(remoteCatalogURL: url)
        let empty: @Sendable () -> CatalogDocument = { CatalogDocument(schemaVersion: 1, updatedAt: nil, models: []) }
        let good = CatalogService(
            bundled: empty, api: HuggingFaceAPI(http: FakeHTTP(body: remoteJSON(title: "good"))),
            cacheDirectory: cache, settings: { settings })
        try await good.refreshRemote()
        let bad = CatalogService(
            bundled: empty, api: HuggingFaceAPI(http: FakeHTTP(body: "not json")),
            cacheDirectory: cache, settings: { settings })
        await #expect(throws: (any Error).self) { try await bad.refreshRemote() }
        #expect(try await bad.entries().map(\.title) == ["good"])
        let newer = CatalogService(
            bundled: empty, api: HuggingFaceAPI(http: FakeHTTP(body: #"{"schemaVersion":7,"models":[]}"#)),
            cacheDirectory: cache, settings: { settings })
        await #expect(throws: LocalModelError.unsupportedCatalogVersion(7)) { try await newer.refreshRemote() }
    }

    @Test func httpErrorsAndPlainHTTPAreRefused() async {
        let empty: @Sendable () -> CatalogDocument = { CatalogDocument(schemaVersion: 1, updatedAt: nil, models: []) }
        let https = CatalogSettings(remoteCatalogURL: URL(string: "https://example.org/c.json"))
        let failing = CatalogService(
            bundled: empty, api: HuggingFaceAPI(http: FakeHTTP(status: 500)),
            cacheDirectory: makeTempDirectory(), settings: { https })
        await #expect(throws: LocalModelError.http(status: 500)) { try await failing.refreshRemote() }

        let plain = CatalogSettings(remoteCatalogURL: URL(string: "http://example.org/c.json"))
        let insecure = CatalogService(
            bundled: empty, api: HuggingFaceAPI(http: FakeHTTP(body: remoteJSON(title: "x"))),
            cacheDirectory: makeTempDirectory(), settings: { plain })
        await #expect(throws: (any Error).self) { try await insecure.refreshRemote() }
    }

}

/// A fake HTTP layer that records requests and can answer with headers.
private final class RecordingHTTP: HTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [URLRequest] = []
    private let respond: @Sendable (URLRequest) -> (String, Int, [String: String])

    init(_ respond: @escaping @Sendable (URLRequest) -> (String, Int, [String: String])) {
        self.respond = respond
    }

    var requests: [URLRequest] { lock.withLock { seen } }

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { seen.append(request) }
        let (body, status, headers) = respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), response)
    }
}

struct SharedCatalogTests {
    private let empty: @Sendable () -> CatalogDocument = { CatalogDocument(schemaVersion: 1, updatedAt: nil, models: []) }

    private static func remoteJSON(_ models: String) -> String { #"{"schemaVersion":1,"models":[\#(models)]}"# }

    private static func mlxJSON(repo: String, title: String, extra: String = "") -> String {
        #"{"repo":"\#(repo)","format":"mlx","title":"\#(title)"\#(extra)}"#
    }

    @Test func theDefaultCatalogIsTheProductionFileOnGitHubAndTheSwitchSelectsTheDevFile() {
        var settings = CatalogSettings()
        #expect(settings.effectiveCatalogURL == CatalogSource.productionURL)
        #expect(CatalogSource.productionURL.absoluteString.hasSuffix("/main/catalog/models.json"))
        settings.useDevelopmentCatalog = true
        #expect(settings.effectiveCatalogURL == CatalogSource.developmentURL)
        #expect(CatalogSource.developmentURL.absoluteString.hasSuffix("/main/catalog/dev-models.json"))
        settings.remoteCatalogURL = URL(string: "https://example.org/mine.json")
        #expect(settings.effectiveCatalogURL.absoluteString == "https://example.org/mine.json", "a custom URL wins over both")
        #expect(CatalogSettings.isAcceptableRemoteCatalogURL(CatalogSource.productionURL))
        #expect(CatalogSettings.isAcceptableRemoteCatalogURL(CatalogSource.developmentURL))
    }

    @Test func settingsSavedBeforeTheDevSwitchStillLoadWithTheirUserModels() throws {
        let old = #"{"userModels":[{"repo":"org/mine","format":"mlx","title":"Mine"}],"remoteCatalogURL":"https://example.org/c.json"}"#
        let settings = try JSONDecoder().decode(CatalogSettings.self, from: Data(old.utf8))
        #expect(settings.userModels.map(\.repo) == ["org/mine"])
        #expect(settings.useDevelopmentCatalog == false)
    }

    @Test func refreshFetchesTheDefaultURLWhenNoneIsSet() async throws {
        let http = RecordingHTTP { _ in (Self.remoteJSON(Self.mlxJSON(repo: "org/r", title: "R")), 200, [:]) }
        let service = CatalogService(
            bundled: empty, api: HuggingFaceAPI(http: http), cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        #expect(try await service.refreshRemote())
        #expect(http.requests.map(\.url) == [CatalogSource.productionURL])
        #expect(try await service.entries().map(\.title) == ["R"])
    }

    @Test func theDevelopmentSwitchFetchesAndCachesTheDevFileSeparately() async throws {
        let http = RecordingHTTP { _ in (Self.remoteJSON(Self.mlxJSON(repo: "org/dev", title: "Dev")), 200, [:]) }
        let cache = makeTempDirectory()
        let dev = CatalogSettings(useDevelopmentCatalog: true)
        let service = CatalogService(bundled: empty, api: HuggingFaceAPI(http: http), cacheDirectory: cache, settings: { dev })
        try await service.refreshRemote()
        #expect(http.requests.map(\.url) == [CatalogSource.developmentURL])
        let production = CatalogService(bundled: empty, cacheDirectory: cache, settings: { CatalogSettings() })
        #expect(try await production.entries().isEmpty, "the production catalog never shows the dev cache")
    }

    @Test func aSecondRefreshSendsTheETagAndA304KeepsTheCachedCopy() async throws {
        let http = RecordingHTTP { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" { return ("", 304, [:]) }
            return (Self.remoteJSON(Self.mlxJSON(repo: "org/r", title: "R")), 200, ["ETag": "\"v1\""])
        }
        let service = CatalogService(
            bundled: empty, api: HuggingFaceAPI(http: http), cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        #expect(try await service.refreshRemote())
        #expect(http.requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(try await service.refreshRemote() == false, "304 means nothing changed")
        #expect(http.requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(try await service.entries().map(\.title) == ["R"])
    }

    @Test func aNewETagReplacesTheCachedCopy() async throws {
        let version = LockedBox("v1")
        let http = RecordingHTTP { request in
            let current = version.value
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"\(current)\"" { return ("", 304, [:]) }
            return (Self.remoteJSON(Self.mlxJSON(repo: "org/r", title: current)), 200, ["ETag": "\"\(current)\""])
        }
        let service = CatalogService(
            bundled: empty, api: HuggingFaceAPI(http: http), cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        try await service.refreshRemote()
        version.value = "v2"
        #expect(try await service.refreshRemote())
        #expect(try await service.entries().map(\.title) == ["v2"])
    }

    @Test func noETagIsSentWithoutACachedBody() async throws {
        let http = RecordingHTTP { _ in (Self.remoteJSON(Self.mlxJSON(repo: "org/r", title: "R")), 200, ["ETag": "\"v1\""]) }
        let cache = makeTempDirectory()
        let first = CatalogService(bundled: empty, api: HuggingFaceAPI(http: http), cacheDirectory: cache, settings: { CatalogSettings() })
        try await first.refreshRemote()
        for file in try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            try FileManager.default.removeItem(at: file)
        }
        try await first.refreshRemote()
        #expect(http.requests[1].value(forHTTPHeaderField: "If-None-Match") == nil, "an ETag without its body would leave an empty catalog")
    }

    @Test func remoteEntriesBeatBundledOnesAndUserEntriesAreAlwaysKept() async throws {
        let bundled = CatalogDocument(schemaVersion: 1, updatedAt: nil, models: [
            sampleMLX(repo: "org/shared", order: 0, title: "Bundled"), sampleMLX(repo: "org/only-bundled", order: 1, title: "Old"),
        ])
        let http = RecordingHTTP { _ in (Self.remoteJSON(Self.mlxJSON(repo: "org/shared", title: "Remote", extra: #","order":0"#)), 200, [:]) }
        let mine = sampleMLX(repo: "org/mine", order: 5, title: "Mine")
        let service = CatalogService(
            bundled: { bundled }, api: HuggingFaceAPI(http: http), cacheDirectory: makeTempDirectory(),
            settings: { CatalogSettings(userModels: [mine]) })
        try await service.refreshRemote()
        let entries = try await service.entries()
        #expect(entries.first { $0.repo == "org/shared" }?.title == "Remote")
        #expect(entries.contains { $0.repo == "org/only-bundled" }, "a remote file that omits a bundled model does not remove it")
        #expect(entries.contains { $0.repo == "org/mine" && $0.origin == .user })
    }

    @Test func aBadRemoteFileIsIgnoredAndTheBundledCatalogStillLoads() async throws {
        let bundled = CatalogDocument(schemaVersion: 1, updatedAt: nil, models: [sampleMLX(repo: "org/bundled", order: 0)])
        for body in ["not json", #"{"schemaVersion":99,"models":[]}"#, #"{"schemaVersion":1,"models":[{"repo":"../x","format":"mlx","title":"x"}]}"#] {
            let http = RecordingHTTP { _ in (body, 200, [:]) }
            let service = CatalogService(
                bundled: { bundled }, api: HuggingFaceAPI(http: http), cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
            await #expect(throws: (any Error).self) { try await service.refreshRemote() }
            #expect(try await service.entries().map(\.repo) == ["org/bundled"])
        }
    }

    @Test func entriesForOtherPlatformsAreHidden() async throws {
        let bundled = CatalogDocument(schemaVersion: 1, updatedAt: nil, models: [
            CatalogEntry(repo: "org/phone", format: .mlx, title: "Phone", platforms: ["ios"]),
            CatalogEntry(repo: "org/tablet", format: .mlx, title: "Tablet", platforms: ["ipados"]),
            CatalogEntry(repo: "org/mac", format: .mlx, title: "Mac", platforms: ["macos"]),
            CatalogEntry(repo: "org/any", format: .mlx, title: "Any"),
        ])
        let service = CatalogService(bundled: { bundled }, cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        #expect(Set(try await service.entries().map(\.repo)) == ["org/phone", "org/tablet", "org/any"])
    }

    @Test func newFieldsDecodeAndOldEntriesStillDo() throws {
        let json = #"""
        {"schemaVersion":1,"models":[
         {"repo":"org/m-GGUF","format":"gguf","file":"m-Q4_K_M.gguf","title":"M","sha256":"\#(String(repeating: "A", count: 64))",
          "iconKey":"liquid","badges":[{"label":"New","tone":"success"},{"label":"Plain"}],"supportsThinking":true,
          "vision":{"mmprojFile":"mmproj-m.gguf","mmprojSize":350000000},"isOnboarding":true,"platforms":["ios"],
          "recommended":true,"minRAMBytes":6000000000,"createdAt":"2026-11-26","updatedAt":"2026-11-27"},
         {"repo":"org/old","format":"mlx","title":"Old"}]}
        """#
        let models = try CatalogDocument.decode(Data(json.utf8)).models
        let m = models[0]
        #expect(m.sha256 == String(repeating: "a", count: 64), "sha256 is stored lowercase")
        #expect(m.iconKey == "liquid")
        #expect(m.badges == [CatalogBadge(label: "New", tone: "success"), CatalogBadge(label: "Plain", tone: nil)])
        #expect(m.supportsThinking && m.isOnboarding && m.recommended)
        #expect(m.vision == CatalogVision(mmprojFile: "mmproj-m.gguf", mmprojSize: 350_000_000))
        #expect(m.platforms == ["ios"] && m.minRAMBytes == 6_000_000_000)
        #expect(m.createdAt == "2026-11-26" && m.updatedAt == "2026-11-27")
        let old = models[1]
        #expect(old.badges.isEmpty && !old.supportsThinking && !old.isOnboarding && !old.recommended)
        #expect(old.vision == nil && old.platforms == nil && old.sha256 == nil)
        // Round trip keeps the new fields and does not invent defaults for old entries.
        let again = try JSONDecoder().decode(CatalogEntry.self, from: JSONEncoder().encode(m))
        #expect(again == m)
        let oldJSON = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!oldJSON.contains("badges") && !oldJSON.contains("isOnboarding"))
    }

    @Test func everyBundledGGUFPinsItsFileWithASha256() throws {
        let doc = try BundledCatalog.load()
        for model in doc.models where model.format == .gguf {
            #expect(model.sha256?.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil, "\(model.id) needs a pinned sha256")
        }
        #expect(doc.models.contains { $0.isOnboarding }, "onboarding needs at least one flagged model")
    }

    @Test func aPinnedSha256IsPassedToTheInstallerAndAChangedFileIsRefused() throws {
        let pinned = String(repeating: "a", count: 64)
        var entry = sampleGGUF(repo: "org/m", file: "m.gguf")
        entry.sha256 = pinned
        let listed = HFFile(path: "m.gguf", size: 1_000, sha256: pinned)
        #expect(try RepoFiles.downloadPlan(for: entry, files: [listed]).first?.sha256 == pinned)
        let noOid = HFFile(path: "m.gguf", size: 1_000, sha256: nil)
        #expect(try RepoFiles.downloadPlan(for: entry, files: [noOid]).first?.sha256 == pinned, "the pin is verified even when the listing has no oid")
        let swapped = HFFile(path: "m.gguf", size: 1_000, sha256: String(repeating: "b", count: 64))
        #expect(throws: LocalModelError.checksumMismatch("m.gguf")) {
            _ = try RepoFiles.downloadPlan(for: entry, files: [swapped])
        }
    }
}

private final class LockedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String
    init(_ value: String) { stored = value }
    var value: String {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
