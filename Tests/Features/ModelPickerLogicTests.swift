import Foundation
import Testing
@testable import AnyRouter

struct ModelPickerLogicTests {
    private let models = [
        testModel(id: "gguf/org/zeta/z.gguf", source: .gguf),
        testModel(id: "apple/foundation", source: .apple),
        testModel(id: "anyrouter/openai/gpt", source: .anyrouter),
        testModel(id: "mlx/org/alpha", source: .mlx),
        testModel(id: "mlx/org/not-installed", source: .mlx, installed: false),
    ]

    @Test func groupsFollowAppleCloudLocalOrder() {
        let kinds = ModelPickerLogic.sections(models: models, query: "").map(\.kind)
        #expect(kinds == [.apple, .anyrouter, .local])
    }

    @Test func localGroupMergesFormatsSortsByNameAndSkipsUninstalled() {
        let local = ModelPickerLogic.sections(models: models, query: "").first { $0.kind == .local }
        // Sorted by display name, which the test helper sets to the id.
        #expect(local?.models.map(\.id) == ["gguf/org/zeta/z.gguf", "mlx/org/alpha"])
        #expect(local?.models.contains { !$0.isInstalled } == false)
    }

    @Test func cloudGroupStaysEmptyWhenSignedOutSoThePromptHasAHome() {
        let local = models.filter { $0.source != .anyrouter }
        let cloud = ModelPickerLogic.sections(models: local, query: "").first { $0.kind == .anyrouter }
        #expect(cloud != nil)
        #expect(cloud?.models.isEmpty == true)
    }

    @Test func queryFiltersAndDropsEmptyGroups() {
        let sections = ModelPickerLogic.sections(models: models, query: "ALPHA")
        #expect(sections.map(\.kind) == [.local])
        #expect(sections.first?.models.map(\.id) == ["mlx/org/alpha"])
    }

    @Test func subtitleShowsSourceAndSize() {
        #expect(ModelPickerLogic.subtitle(for: testModel(source: .apple)) == "On device")
        #expect(ModelPickerLogic.subtitle(for: testModel(source: .anyrouter)) == "Cloud")
        var gguf = testModel(source: .gguf)
        gguf.sizeBytes = 1_000_000_000
        #expect(ModelPickerLogic.subtitle(for: gguf).hasPrefix("GGUF · "))
    }
}
