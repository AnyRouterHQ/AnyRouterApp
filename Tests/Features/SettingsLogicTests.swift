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

    @Test func licenseListCoversLinkedLibraries() {
        let names = LicenseNotice.all.map(\.name)
        #expect(names.contains("llama.cpp"))
        #expect(names.contains("MarkdownUI"))
        #expect(LicenseNotice.all.allSatisfy { !$0.copyright.isEmpty && !$0.license.isEmpty })
    }
}
