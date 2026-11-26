import Foundation
import Testing
@testable import AnyRouter

struct CatalogSourcesLogicTests {
    private func entry(_ id: String, repo: String = "", user: Bool = false, source: ModelSource = .gguf, revision: String? = nil) -> LocalModelEntry {
        LocalModelEntry(
            descriptor: testModel(id: id, source: source), summary: "", tags: [], fit: .fits, isUserAdded: user,
            repo: repo, revision: revision)
    }

    private func sources(_ entries: [LocalModelEntry], remote: String = "", dev: Bool = false) -> [LocalCatalogSource] {
        CatalogSourcesLogic.sources(catalog: entries, remoteURL: remote, usesDevelopmentCatalog: dev)
    }

    private var mixed: [LocalModelEntry] {
        [
            entry("s1"), entry("s2"),
            entry("u1", repo: "org/a", user: true, revision: "abc123"), entry("u2", repo: "org/a", user: true, revision: "abc123"),
            entry("u3", repo: "org/b", user: true, source: .mlx),
        ]
    }

    @Test func theSharedCatalogComesFirstThenOneSourcePerRepoAndFormat() {
        let list = sources(mixed)
        #expect(list.map(\.id) == ["catalog", "gguf/org/a", "mlx/org/b"])
        #expect(list[0].models.map(\.id) == ["s1", "s2"])
        #expect(list[1].models.map(\.id) == ["u1", "u2"])
        #expect(list[1].title == "org/a" && list[1].address == "org/a")
        #expect(list[1].format == "GGUF" && list[2].format == "MLX")
        #expect(list[1].revision == "abc123" && list[2].revision == nil)
    }

    @Test func theCatalogSourceNamesTheAddressInUse() {
        let normal = sources([])[0]
        #expect(normal.title == "AnyRouter catalog")
        #expect(normal.address == CatalogSource.productionURL.absoluteString)
        let dev = sources([], dev: true)[0]
        #expect(dev.title == "AnyRouter catalog (development)")
        #expect(dev.address == CatalogSource.developmentURL.absoluteString)
        let custom = sources([], remote: "https://example.org/models.json", dev: true)[0]
        #expect(custom.title == "Custom catalog")
        #expect(custom.address == "https://example.org/models.json")
        #expect(custom.format == nil)
    }

    @Test func kindsHaveNamesAndOnlyReposCanBeRemoved() {
        let list = sources(mixed)
        #expect(list[0].typeName == "Model catalog" && !list[0].isRemovable)
        #expect(list[1].typeName == "Hugging Face repo" && list[1].isRemovable)
    }

    @Test func subtitleCountsModels() {
        let list = sources(mixed)
        #expect(CatalogSourcesLogic.subtitle(list[0]) == "Model catalog · 2 models")
        #expect(CatalogSourcesLogic.subtitle(list[1]) == "GGUF · 2 models")
        #expect(CatalogSourcesLogic.subtitle(list[2]) == "MLX · 1 model")
    }

    @Test func aSourceWithAnInstalledModelCannotBeRemovedBecauseTheFilesWouldBecomeUnreachable() {
        let list = sources(mixed)
        #expect(CatalogSourcesLogic.canRemove(list[1], state: { _ in .notInstalled }))
        #expect(!CatalogSourcesLogic.canRemove(list[1], state: { $0 == "u2" ? .installed : .notInstalled }))
        #expect(!CatalogSourcesLogic.canRemove(list[0], state: { _ in .notInstalled }), "the shared catalog is never removed")
    }
}
