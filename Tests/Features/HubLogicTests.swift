import Foundation
import Testing
@testable import AnyRouter

struct HubLogicTests {
    private func entry(_ id: String, title: String, summary: String = "", tags: [String] = []) -> LocalModelEntry {
        LocalModelEntry(descriptor: testModel(id: id, source: .gguf).withName(title), summary: summary,
                        tags: tags, fit: .fits, isUserAdded: false)
    }

    private let states: [String: DownloadState] = [
        "a": .installed, "b": .downloading(progress: 0.4), "c": .notInstalled, "d": .failed("x"),
    ]

    private func sections(_ query: String, catalog: [LocalModelEntry]) -> HubLogic.Sections {
        HubLogic.sections(catalog: catalog, state: { states[$0] ?? .notInstalled }, query: query)
    }

    @Test func installedSplitsFromEverythingElse() {
        let catalog = ["a", "b", "c", "d"].map { entry($0, title: $0) }
        let s = sections("", catalog: catalog)
        #expect(s.installed.map(\.id) == ["a"])
        #expect(s.available.map(\.id) == ["b", "c", "d"])
    }

    @Test func queryMatchesTitleSummaryAndTags() {
        let catalog = [
            entry("a", title: "Gemma"), entry("b", title: "Other", summary: "great for translation"),
            entry("c", title: "Third", tags: ["vision"]),
        ]
        #expect(sections("gem", catalog: catalog).installed.map(\.id) == ["a"])
        #expect(sections("TRANSLATION", catalog: catalog).available.map(\.id) == ["b"])
        #expect(sections("vision", catalog: catalog).available.map(\.id) == ["c"])
        #expect(sections("nothing", catalog: catalog).isEmpty)
    }

    @Test func percentClampsAndHandlesUnknownTotals() {
        #expect(HubLogic.percent(0.456) == "46%")
        #expect(HubLogic.percent(1.7) == "100%")
        #expect(HubLogic.percent(nil) == "…")
    }

    @Test func activeStatesAreDownloadingPausedVerifying() {
        #expect(DownloadState.downloading(progress: nil).isActive)
        #expect(DownloadState.paused(progress: 0.1).isActive)
        #expect(DownloadState.verifying.isActive)
        #expect(!DownloadState.installed.isActive)
        #expect(!DownloadState.failed("x").isActive)
    }
}

private extension ModelDescriptor {
    func withName(_ name: String) -> ModelDescriptor {
        var copy = self
        copy.displayName = name
        return copy
    }
}
