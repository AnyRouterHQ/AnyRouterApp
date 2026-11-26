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

    @Test func refreshWithoutAURLDoesNothing() async throws {
        let service = CatalogService(
            bundled: { CatalogDocument(schemaVersion: 1, updatedAt: nil, models: []) },
            cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        #expect(try await service.refreshRemote() == false)
    }
}
