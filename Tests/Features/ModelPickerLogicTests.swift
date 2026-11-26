import Foundation
import Testing
@testable import AnyRouter

struct ModelPickerLogicTests {
    private func cloud(_ wire: String, name: String? = nil, summary: String? = nil, usable: Bool = true) -> ModelDescriptor {
        ModelDescriptor(id: "anyrouter/\(wire)", source: .anyrouter, displayName: name ?? wire, contextLength: nil,
                        capabilities: ["chat"], sizeBytes: nil, isInstalled: usable, summary: summary)
    }

    private func router(_ slug: String, summary: String? = nil) -> ModelDescriptor {
        cloud("anyrouter/\(slug)", name: "AnyRouter \(slug.capitalized)", summary: summary)
    }

    private var catalog: [ModelDescriptor] {
        [
            router("byok"), router("coding", summary: "Best for code. Uses the strongest coder."), router("agent"),
            router("hermes"), router("free"), router("auto"), router("decision"), router("latest"),
            cloud("openai/gpt-5"), cloud("anthropic/claude-sonnet"), cloud("google/gemini-pro"),
            cloud("anthropic/claude-haiku"),
            testModel(id: "gguf/org/zeta/z.gguf", source: .gguf),
            testModel(id: "apple/foundation", source: .apple),
            testModel(id: "mlx/org/alpha", source: .mlx),
            testModel(id: "mlx/org/not-installed", source: .mlx, installed: false),
        ]
    }

    private func ids(_ section: PickerSection?) -> [String] { section?.models.map(\.id) ?? [] }
    private func section(_ kind: PickerSection.Kind, query: String = "") -> PickerSection? {
        ModelPickerLogic.sections(models: catalog, query: query).first { $0.kind == kind }
    }

    @Test func groupsAreAppleRoutersLocalThenProviders() {
        let kinds = ModelPickerLogic.sections(models: catalog, query: "").map(\.kind)
        #expect(kinds == [.apple, .anyrouter, .local, .provider("anthropic"), .provider("google"), .provider("openai")])
    }

    @Test func autoComesFirstShownAsAnyRouterThenTheOtherRoutersInOrder() {
        let routers = section(.anyrouter)?.models ?? []
        #expect(routers.first?.id == ModelDescriptor.autoRouterID)
        #expect(routers.first?.shortName == "AnyRouter")
        // Named routers first, the rest alphabetical.
        #expect(routers.map(\.wireID) == [
            "anyrouter/auto", "anyrouter/coding", "anyrouter/agent", "anyrouter/free",
            "anyrouter/latest", "anyrouter/decision", "anyrouter/hermes",
        ])
    }

    @Test func byokIsHiddenByDefaultButFoundBySearch() {
        let all = ModelPickerLogic.sections(models: catalog, query: "").flatMap(\.models)
        #expect(!all.contains { $0.id == ModelDescriptor.byokRouterID })
        let found = ModelPickerLogic.sections(models: catalog, query: "byok").flatMap(\.models)
        #expect(found.map(\.id) == [ModelDescriptor.byokRouterID])
    }

    @Test func cloudModelsGroupByProviderAndSortByName() {
        #expect(ids(section(.provider("anthropic"))) == ["anyrouter/anthropic/claude-haiku", "anyrouter/anthropic/claude-sonnet"])
        #expect(section(.provider("anthropic"))?.title == "Anthropic")
        #expect(section(.provider("openai"))?.title == "OpenAI")
    }

    @Test func searchMatchesNameIdAndProviderButNotThePrefix() {
        let byProvider = ModelPickerLogic.sections(models: catalog, query: "anthropic").flatMap(\.models)
        #expect(byProvider.count == 2)
        let byName = ModelPickerLogic.sections(models: catalog, query: "GEMINI").flatMap(\.models)
        #expect(byName.map(\.id) == ["anyrouter/google/gemini-pro"])
        // "anyrouter" matches the routers by name, not every cloud model through the id prefix.
        let prefix = ModelPickerLogic.sections(models: catalog, query: "anyrouter").flatMap(\.models)
        #expect(!prefix.contains { $0.cloudProvider == "openai" })
    }

    @Test func localGroupMergesFormatsSortsByNameAndSkipsUninstalled() {
        // Sorted by display name, which the test helper sets to the id.
        #expect(ids(section(.local)) == ["gguf/org/zeta/z.gguf", "mlx/org/alpha"])
    }

    @Test func routerGroupStaysEmptyWhenSignedOutSoThePromptHasAHome() {
        let signedOut = catalog.map { model -> ModelDescriptor in
            var copy = model
            if copy.source == .anyrouter { copy.isInstalled = false }
            return copy
        }
        let sections = ModelPickerLogic.sections(models: signedOut, query: "")
        #expect(sections.map(\.kind) == [.apple, .anyrouter, .local])
        #expect(sections.first { $0.kind == .anyrouter }?.models.isEmpty == true)
    }

    @Test func queryDropsEmptyGroupsAndTheSignInGroup() {
        let sections = ModelPickerLogic.sections(models: catalog, query: "ALPHA")
        #expect(sections.map(\.kind) == [.local])
    }

    @Test func fiveHundredModelsStayGroupedAndCheap() {
        var big = catalog
        for i in 0..<500 { big.append(cloud("vendor\(i % 25)/model-\(i)")) }
        let sections = ModelPickerLogic.sections(models: big, query: "")
        #expect(sections.flatMap(\.models).count == big.count - 2) // byok and the uninstalled local
        #expect(sections.filter { if case .provider = $0.kind { true } else { false } }.count == 28)
    }

    @Test func subtitlesExplainEachKindOfModel() {
        #expect(ModelPickerLogic.subtitle(for: testModel(source: .apple)) == "On device")
        #expect(ModelPickerLogic.subtitle(for: router("auto")) == "Picks the best model for each message")
        #expect(ModelPickerLogic.subtitle(for: router("coding", summary: "Best for code. Uses the strongest coder.")) == "Best for code")
        #expect(ModelPickerLogic.subtitle(for: router("agent")) == "AnyRouter")
        #expect(ModelPickerLogic.subtitle(for: cloud("openai/gpt-5")) == "OpenAI")
        var gguf = testModel(source: .gguf)
        gguf.sizeBytes = 1_000_000_000
        #expect(ModelPickerLogic.subtitle(for: gguf).hasPrefix("GGUF · "))
    }

    @Test func longDescriptionsAreCutToOneLine() {
        let long = String(repeating: "word ", count: 40)
        #expect(ModelPickerLogic.shortSummary(long).count <= 80)
        #expect(ModelPickerLogic.shortSummary("First line\nSecond line") == "First line")
    }
}
