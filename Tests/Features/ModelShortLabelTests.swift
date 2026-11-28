import Foundation
import Testing
@testable import AnyRouter

struct ModelShortLabelTests {
    /// One name everywhere (picker rows, the chat header, reply footers, switch notes, Local Models): family and size.
    @Test func onDeviceModelsGoByFamilyAndSizeAndKeepTheVariantForTheDetailLine() {
        let gemma = localModel("gguf/google/gemma-4-E2B-it-qat-GGUF/gemma-4-E2B-it-qat-Q4_0.gguf", name: "Gemma 4 E2B (Q4_0 (QAT))")
        #expect(ModelShortLabel.name(of: gemma) == "Gemma 4 E2B")
        #expect(ModelShortLabel.variant(of: gemma) == "Q4_0 QAT")
        #expect(gemma.shortName == "Gemma 4 E2B", "the chat header and footers use the same name")

        let qwen = localModel("gguf/Qwen/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q4_K_M.gguf", name: "Qwen3 0.6B")
        #expect(ModelShortLabel.name(of: qwen) == "Qwen3 0.6B")
        #expect(ModelShortLabel.variant(of: qwen) == "GGUF Q4_K_M", "no bracket: the format read from the file")

        let mlx = localModel("mlx/mlx-community/Qwen3-4B-4bit", name: "Qwen3 4B", source: .mlx)
        #expect(ModelShortLabel.name(of: mlx) == "Qwen3 4B")
        #expect(ModelShortLabel.variant(of: mlx) == "MLX 4-bit")

        let empty = localModel("gguf/o/r/f.gguf", name: "Odd ()")
        #expect(ModelShortLabel.name(of: empty) == "Odd")
        #expect(ModelShortLabel.variant(of: empty) == "GGUF", "an empty bracket falls back to the format")

        let apple = testModel(id: "apple/foundation", source: .apple)
        #expect(ModelShortLabel.name(of: apple) == apple.displayName)
        #expect(ModelShortLabel.variant(of: apple) == nil)

        var auto = testModel(id: ModelDescriptor.autoRouterID, source: .anyrouter)
        auto.displayName = "AnyRouter Auto"
        #expect(ModelShortLabel.name(of: auto) == "AnyRouter")
        let cloud = cloudModel("anthropic/claude-sonnet", name: "Claude Sonnet (thinking)")
        #expect(ModelShortLabel.name(of: cloud) == "Claude Sonnet (thinking)", "cloud names stay as AnyRouter writes them")
    }

    @Test(arguments: [
        // On-device models, as the catalog and the engines name them.
        ("Gemma 4 E2B", "Gemma 4 E2B"),
        ("Gemma 4 E2B (Q4_0 (QAT))", "Gemma 4 E2B"),
        ("Llama 3.2 3B", "Llama 3.2 3B"),
        ("Qwen 3.5 0.8B", "Qwen 3.5 0.8B"),
        ("Apple Intelligence", "Apple"),
        ("Apple Foundation Model", "Apple"),
        ("Apple Intelligence (Cloud)", "Apple Cloud"),
        // Cloud models, as the AnyRouter list names them.
        ("AnyRouter", "AnyRouter"),
        ("AnyRouter Auto", "AnyRouter Auto"),
        ("GPT-6.2 Sol", "GPT-6.2 Sol"),
        ("Amos 1 Large", "Amos 1 Large"),
        ("Google gemini-flash (latest)", "gemini-flash"),
        ("Claude Haiku 4.5", "Haiku 4.5"),
        ("Anthropic: Claude Sonnet 4.6", "Sonnet 4.6"),
        ("Meta Llama 3.3 70B", "Llama 3.3 70B"),
        ("Nemotron 3.5 Bolt E4B", "Nemotron 3.5"),
        ("Nemotron 3.5 Lightning 30B A3B", "Nemotron 3.5"),
        ("Nemotron 3 Ultra 550B", "Nemotron 3"),
        ("Qwen 2.5 Coder 32B", "Qwen 2.5 Coder"),
    ])
    func realNamesGetTheirShortForm(name: String, label: String) {
        #expect(ModelShortLabel.make(name) == label)
    }

    @Test func aLoneLongWordIsNeverCut() {
        #expect(ModelShortLabel.make("Supercalifragilistic") == "Supercalifragilistic")
        #expect(ModelShortLabel.make("Claude") == "Claude")
        #expect(ModelShortLabel.make("Google") == "Google")
    }

    @Test func anEmptyNameStaysEmpty() {
        #expect(ModelShortLabel.make("").isEmpty)
        #expect(ModelShortLabel.make("   ").isEmpty)
    }

    @Test func everyModelOfTheBundledCatalogGetsAShortReadableLabel() throws {
        let names = try BundledCatalog.load().models.map { $0.descriptor(isInstalled: false).displayName }
        let labels = names.map(ModelShortLabel.make)
        #expect(!names.isEmpty)
        #expect(labels.contains("Gemma 4 E2B"))
        let tooLong = zip(names, labels).filter { $0.1.isEmpty || $0.1.count > ModelShortLabel.maxLength }.map(\.0)
        #expect(tooLong.isEmpty, "no short label for: \(tooLong)")
    }
}
