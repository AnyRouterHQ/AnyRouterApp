import Testing
@testable import AnyRouter

struct SettingsLogicTests {
    @Test(arguments: [
        ("org/model", "org/model"),
        ("  org/model-GGUF  ", "org/model-GGUF"),
        ("https://huggingface.co/org/model", "org/model"),
        ("https://huggingface.co/org/model/tree/main", "org/model"),
        ("huggingface.co/org/model/", "org/model"),
    ])
    func parsesRepoIDs(input: String, expected: String) {
        #expect(SettingsLogic.parseRepo(input) == expected)
    }

    @Test(arguments: ["", "model", "org/", "/model", "org/mo del", "org/model?x=1", "../model"])
    func rejectsNonRepoInput(input: String) {
        #expect(SettingsLogic.parseRepo(input) == nil)
    }

    @Test func localModelsSubtitleSaysHowManyAndHowMuch() {
        #expect(SettingsLogic.localModelsSubtitle(installedCount: 3, usedBytes: 4_100_000_000) == "3 installed · 4.1 GB")
        #expect(SettingsLogic.localModelsSubtitle(installedCount: 1, usedBytes: 600_000_000) == "1 installed · 600 MB")
        #expect(SettingsLogic.localModelsSubtitle(installedCount: 0, usedBytes: 0) == nil)
    }

    @Test func anyRouterModelsSubtitleLeadsWithTheDefaultThenTheStarredCount() {
        #expect(SettingsLogic.anyRouterModelsSubtitle(defaultName: "AnyRouter", starredCount: 4) == "Default: AnyRouter")
        #expect(SettingsLogic.anyRouterModelsSubtitle(defaultName: nil, starredCount: 4) == "4 starred")
        #expect(SettingsLogic.anyRouterModelsSubtitle(defaultName: nil, starredCount: 0) == nil)
    }

    @Test func licenseListCoversLinkedLibraries() {
        let names = LicenseNotice.all.map(\.name)
        #expect(names.contains("llama.cpp"))
        #expect(names.contains("MarkdownUI"))
        #expect(LicenseNotice.all.allSatisfy { !$0.copyright.isEmpty && !$0.license.isEmpty })
    }
}
