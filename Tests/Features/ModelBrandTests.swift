import Foundation
import Testing
import UIKit
@testable import AnyRouter

struct ModelBrandTests {
    private func brand(_ wire: String) -> ModelBrand { ModelBrand.resolve(cloudModel(wire)) }

    @Test func providerPrefixPicksTheBundledLogo() {
        #expect(brand("openai/gpt-5") == .asset("Logo-openai"))
        #expect(brand("anthropic/claude-sonnet-4-6") == .asset("Logo-anthropic"))
        #expect(brand("google/gemini-2.5-pro") == .asset("Logo-google"))
        #expect(brand("deepseek/deepseek-v4") == .asset("Logo-deepseek"))
        #expect(brand("cohere/command-r") == .asset("Logo-cohere"))
    }

    @Test func aliasesMatchTheWebApp() {
        #expect(brand("meta-llama/llama-4") == .asset("Logo-meta"))
        #expect(brand("mistralai/mistral-large") == .asset("Logo-mistral"))
        #expect(brand("x-ai/grok-4") == .asset("Logo-xai"))
        #expect(brand("z-ai/glm-5") == .asset("Logo-z-ai"))
        #expect(brand("zhipu/glm-4") == .asset("Logo-z-ai"))
        #expect(brand("moonshotai/kimi-k3") == .asset("Logo-moonshotai"))
        #expect(brand("amazon/nova-pro") == .asset("Logo-aws"))
    }

    @Test func routersUseTheAnyRouterMark() {
        #expect(brand("anyrouter/auto") == .asset(ModelBrand.anyRouterMark))
        #expect(brand("anyrouter/free") == .asset(ModelBrand.anyRouterMark))
    }

    @Test func unknownOwnerFallsBackToTheModelFamilyThenAGenericSymbol() {
        #expect(brand("some-host/claude-clone") == .asset("Logo-anthropic"))
        #expect(brand("some-host/qwen3-235b") == .asset("Logo-qwen"))
        #expect(brand("some-host/mystery-1") == .symbol("s.circle.fill"))
    }

    @Test func companiesWithAPublicMarkGetIt() {
        #expect(brand("tencent/hunyuan-a13b") == .asset("Logo-tencent"))
        #expect(brand("ibm-granite/granite-4") == .asset("Logo-ibm"))
        #expect(brand("xiaomi/mimo-v2") == .asset("Logo-xiaomi"))
        #expect(brand("bytedance-seed/seed-2") == .asset("Logo-bytedance"))
        #expect(brand("sentence-transformers/all-minilm") == .asset("Logo-huggingface"))
        #expect(brand("apple/some-cloud-model") == .asset("Logo-apple"))
    }

    @Test func anOwnerWithoutAMarkShowsItsFirstLetter() {
        #expect(brand("thedrummer/cydonia") == .symbol("t.circle.fill"))
        #expect(brand("Sao10K/euryale") == .symbol("s.circle.fill"))
        #expect(ModelBrand.monogram("01-ai") == ModelBrand.unknown)
        #expect(ModelBrand.monogram("") == ModelBrand.unknown)
        #expect(ModelBrand.monogram("écho") == ModelBrand.unknown)
    }

    @Test func everyMonogramIsASystemSymbol() {
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            #expect(UIImage(systemName: "\(letter).circle.fill") != nil, "no symbol for \(letter)")
        }
    }

    @Test func appleUsesTheAppleSymbol() {
        #expect(ModelBrand.resolve(testModel(id: "apple/foundation", source: .apple)) == .symbol("apple.logo"))
    }

    @Test func localModelsUseTheFamilyOfTheRepoThenTheOrg() {
        #expect(ModelBrand.resolve(localModel("gguf/unsloth/gemma-3-1b-it-GGUF/gemma-3-1b-it-Q4_K_M.gguf")) == .asset("Logo-google"))
        #expect(ModelBrand.resolve(localModel("mlx/mlx-community/Qwen3-4B-4bit", source: .mlx)) == .asset("Logo-qwen"))
        #expect(ModelBrand.resolve(localModel("gguf/bartowski/Llama-3.2-1B-Instruct-GGUF/x.gguf")) == .asset("Logo-meta"))
        #expect(ModelBrand.resolve(localModel("gguf/org/Phi-4-mini-GGUF/x.gguf")) == .asset("Logo-microsoft"))
        #expect(ModelBrand.resolve(localModel("gguf/liquid/LFM2-1.2B-GGUF/x.gguf")) == .asset("Logo-liquid"))
        #expect(ModelBrand.resolve(localModel("gguf/org/SmolLM2-360M-GGUF/x.gguf")) == .asset("Logo-huggingface"))
        #expect(ModelBrand.resolve(localModel("gguf/openai/some-oss-GGUF/x.gguf")) == .asset("Logo-openai"))
        #expect(ModelBrand.resolve(localModel("gguf/org/unknown-model-GGUF/x.gguf")) == .symbol("u.circle.fill"))
    }

    @Test func aFamilyWithoutAPublicMarkShowsItsSymbolTile() {
        #expect(ModelBrand.resolve(localModel("gguf/org/Inkling-2-Mini-GGUF/x.gguf")) == .tile("drop.fill"))
        #expect(brand("some-host/inkling-2") == .tile("drop.fill"))
        #expect(UIImage(systemName: "drop.fill") != nil)
        for family in ModelBrand.table.symbols {
            #expect(UIImage(systemName: family.symbol) != nil, "no system symbol \(family.symbol) for \(family.prefix)")
        }
    }

    @Test func aColorMarkIsUsedWhereItReadsAndTheSingleColorMarkElsewhere() {
        #expect(ModelBrand.table.colorMarks["google"] == .any)
        #expect(ModelBrand.colorAsset(for: "Logo-google", dark: false) == "LogoColor-google")
        #expect(ModelBrand.colorAsset(for: "Logo-google", dark: true) == "LogoColor-google")
        #expect(ModelBrand.table.colorMarks["aws"] == .light)
        #expect(ModelBrand.colorAsset(for: "Logo-aws", dark: false) == "LogoColor-aws")
        #expect(ModelBrand.colorAsset(for: "Logo-aws", dark: true) == nil, "black parts vanish in dark mode")
        #expect(ModelBrand.colorAsset(for: "Logo-openai", dark: false) == nil, "no color mark: the template")
        #expect(ModelBrand.colorAsset(for: ModelBrand.anyRouterMark, dark: false) == nil)
    }

    @Test func everyColorMarkShipsItsImage() {
        for slug in ModelBrand.table.colorMarks.keys {
            #expect(UIImage(named: "LogoColor-\(slug)") != nil, "LogoColor-\(slug) is missing from the asset catalog")
            #expect(ModelBrand.table.brands[slug] != nil)
        }
    }

    @Test func aLogoFromTheAPIWins() throws {
        var model = cloudModel("openai/gpt-5")
        model.cloud?.logoURL = URL(string: "https://example.com/openai.png")
        #expect(ModelBrand.resolve(model) == .remote(try #require(URL(string: "https://example.com/openai.png"))))
    }

    @Test func aSavedIdResolvesWithoutTheModelList() {
        #expect(ModelBrand.resolve(id: "anyrouter/openai/gpt-5") == .asset("Logo-openai"))
        #expect(ModelBrand.resolve(id: "apple/foundation") == .symbol("apple.logo"))
        #expect(ModelBrand.resolve(id: "mlx/mlx-community/Qwen3-4B-4bit") == .asset("Logo-qwen"))
        #expect(ModelBrand.resolve(id: "anyrouter/anyrouter/auto") == .asset(ModelBrand.anyRouterMark))
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The live AnyRouter owner list, refreshed by `scripts/logo-coverage.py --refresh`.
    private func fixtureOwners() throws -> [String] {
        let url = repoRoot.appendingPathComponent("Tests/Fixtures/anyrouter-owners.json")
        let ids = try JSONDecoder().decode(OwnerFixture.self, from: Data(contentsOf: url)).ids
        return Set(ids.compactMap { $0.split(separator: "/").first.map(String.init) }).sorted()
    }

    @Test func everyKnownOwnerHasAMarkOrWasReviewedAsMarkless() throws {
        let noMark = Set(ModelBrand.table.noMark)
        let owners = try fixtureOwners()
        try #require(owners.count > 50)
        let unreviewed = owners.filter { $0 != "anyrouter" && ModelBrand.slug(owner: $0, bareName: "") == nil && !noMark.contains($0) }
        #expect(unreviewed.isEmpty, "no logo for \(unreviewed): add one with scripts/logo-add.py or list it under noMark")
        let stale = noMark.filter { ModelBrand.slug(owner: $0, bareName: "") != nil || !owners.contains($0) }
        #expect(stale.isEmpty, "noMark lists owners that are gone or now have a mark: \(stale.sorted())")
    }

    @Test func everyLocalCatalogRepoHasAMark() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("catalog/models.json"))
        let repos = try JSONDecoder().decode(CatalogRepos.self, from: data).families.flatMap(\.variants).map(\.repo)
        try #require(!repos.isEmpty)
        for repo in repos {
            switch ModelBrand.resolve(localModel("gguf/\(repo)/x.gguf")) {
            case .asset, .tile: continue
            case .remote, .symbol:
                Issue.record("local catalog repo without a logo: \(repo)")
                continue
            }
        }
    }

    @Test func everyBundledSlugHasItsImageInTheAssetCatalog() throws {
        let root = repoRoot.appendingPathComponent("Design/Assets.xcassets")
        try #require(FileManager.default.fileExists(atPath: root.path))
        for slug in ModelBrand.bundledSlugs {
            let dir = root.appendingPathComponent("Logo-\(slug).imageset/\(slug).svg")
            #expect(FileManager.default.fileExists(atPath: dir.path), "missing logo for \(slug)")
        }
    }
}

private struct OwnerFixture: Decodable { let ids: [String] }

private struct CatalogRepos: Decodable {
    struct Family: Decodable {
        struct Variant: Decodable { let repo: String }
        let variants: [Variant]
    }
    let families: [Family]
}
