import Foundation
import Testing
@testable import AnyRouter

struct ModelShortLabelTests {
    @Test(arguments: [
        // On-device models, as the catalog and the engines name them.
        ("Gemma 4 E2B", "Gemma 4 E2B"),
        ("Gemma 4 E2B (Q4_0 (QAT))", "Gemma 4 E2B"),
        ("Llama 3.2 3B", "Llama 3.2 3B"),
        ("Qwen 3.5 0.8B", "Qwen 3.5 0.8B"),
        ("Apple Intelligence", "Apple"),
        ("Apple Foundation Model", "Apple"),
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
