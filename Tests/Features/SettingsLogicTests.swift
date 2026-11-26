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

    @Test func atomicChatNoticeKeepsBothUpstreamCopyrightLines() throws {
        let atomic = try #require(LicenseNotice.all.first { $0.name == "Atomic Chat" })
        #expect(atomic.copyright.contains("Copyright 2026 Atomic Chat (https://atomic.chat)"))
        #expect(atomic.copyright.contains("Copyright 2025 Menlo Research (https://menlo.ai)"))
        #expect(atomic.license.contains("Apache"))
    }
}
