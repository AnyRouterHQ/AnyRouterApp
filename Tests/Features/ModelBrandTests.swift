import Foundation
import Testing
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
        #expect(brand("some-host/mystery-1") == .symbol("cube"))
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
        #expect(ModelBrand.resolve(localModel("gguf/org/unknown-model-GGUF/x.gguf")) == .symbol("cpu"))
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

    @Test func everyBundledSlugHasItsImageInTheAssetCatalog() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Design/Assets.xcassets")
        try #require(FileManager.default.fileExists(atPath: root.path))
        for slug in ModelBrand.bundledSlugs {
            let dir = root.appendingPathComponent("Logo-\(slug).imageset/\(slug).svg")
            #expect(FileManager.default.fileExists(atPath: dir.path), "missing logo for \(slug)")
        }
    }
}
