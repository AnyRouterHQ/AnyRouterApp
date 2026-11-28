import Foundation
import Testing
@testable import AnyRouter

struct SkillImportLogicTests {
    private let markdown = ["Content-Type": "text/markdown; charset=utf-8"]
    private let file = "---\nname: bill-splitter\ndescription: Split a bill.\n---\n1. Ask who paid."

    private func check(url: URL? = URL(string: "https://example.com/x"), status: Int = 200, type: String? = "text/markdown", length: Int64 = 10) throws {
        try SkillImportLogic.check(finalURL: url, status: status, contentType: type, length: length)
    }

    private func importer(_ api: StubbedAPI) -> SkillImporter { SkillImporter(session: api.session) }
    private func link(_ api: StubbedAPI) -> URL { URL(string: "https://\(api.host)/SKILL.md")! }

    @Test func onlyHTTPSLinksAreAccepted() throws {
        #expect(try SkillImportLogic.url(from: "  https://example.com/a/SKILL.md \n").absoluteString == "https://example.com/a/SKILL.md")
        #expect(try SkillImportLogic.url(from: "HTTPS://example.com/x").host == "example.com")
        for bad in ["http://example.com/SKILL.md", "ftp://example.com/x", "file:///etc/passwd", "example.com/SKILL.md", "https://", "", "not a url"] {
            #expect(throws: SkillImportError.notHTTPS) { try SkillImportLogic.url(from: bad) }
        }
    }

    @Test func aResponseMustBeHTTPSSuccessfulTextAndSmall() throws {
        try check()
        try check(type: "text/plain; charset=UTF-8")
        try check(type: " TEXT/Markdown ;x=y", length: -1)
        try check(length: Int64(SkillImportLogic.sizeLimit))
        #expect(throws: SkillImportError.notHTTPS) { try check(url: URL(string: "http://example.com/x")) }
        #expect(throws: SkillImportError.notHTTPS) { try check(url: nil) }
        #expect(throws: SkillImportError.http(404)) { try check(status: 404) }
        #expect(throws: SkillImportError.http(302)) { try check(status: 302) }
        for type in [nil, "text/html", "application/json", "application/octet-stream", ""] {
            #expect(throws: SkillImportError.notText) { try check(type: type) }
        }
        #expect(throws: SkillImportError.tooLarge) { try check(length: Int64(SkillImportLogic.sizeLimit) + 1) }
    }

    @Test func textMustBeUTF8() throws {
        #expect(try SkillImportLogic.text(from: Data("Tiếng Việt".utf8)) == "Tiếng Việt")
        #expect(throws: SkillImportError.unreadable) { try SkillImportLogic.text(from: Data([0xFF, 0xFE, 0x00, 0xD8])) }
    }

    @Test func thePreviewShowsNameDescriptionAndTheFirstLinesOfTheSteps() {
        let short = SkillDraft(name: "bill-splitter", description: "Split a bill.", body: "1. Ask.\n2. Add.")
        #expect(SkillImportLogic.preview(short) == "bill-splitter\nSplit a bill.\n\n1. Ask.\n2. Add.")
        let long = SkillDraft(name: "long", description: "D.", body: (1...10).map { "step \($0)" }.joined(separator: "\n"))
        let text = SkillImportLogic.preview(long)
        #expect(text.contains("step 6") && !text.contains("step 7") && text.hasSuffix("\n\u{2026}"))
        let wide = SkillDraft(name: "wide", description: "D.", body: String(repeating: "w", count: 900))
        let cut = SkillImportLogic.preview(wide)
        #expect(cut.count < 460 && cut.hasSuffix("\n\u{2026}"))
    }

    @Test func everyErrorSaysWhatWentWrong() {
        let all: [SkillImportError] = [.notHTTPS, .http(404), .notText, .tooLarge, .unreadable]
        #expect(Set(all.compactMap(\.errorDescription)).count == 5)
        #expect(SkillImportError.http(404).errorDescription?.contains("404") == true)
    }

    @Test func fetchReadsATextFileAndSendsNoCredentials() async throws {
        let body = file
        let headers = markdown
        let api = StubbedAPI { request in
            let clean = request.value(forHTTPHeaderField: "Authorization") == nil && request.value(forHTTPHeaderField: "Cookie") == nil
            return clean ? StubRegistry.Reply(body: Data(body.utf8), headers: headers) : StubRegistry.Reply(status: 400)
        }
        #expect(try await importer(api).fetch(link(api)) == file)
    }

    @Test func fetchRefusesWhatIsNotASmallTextFile() async {
        let big = Data(repeating: 0x61, count: SkillImportLogic.sizeLimit + 1)
        let cases: [(StubRegistry.Reply, SkillImportError)] = [
            (StubRegistry.Reply(status: 404, body: Data("no".utf8), headers: markdown), .http(404)),
            (StubRegistry.Reply(body: Data("<p>".utf8), headers: ["Content-Type": "text/html"]), .notText),
            (StubRegistry.Reply(body: big, headers: markdown), .tooLarge),
            (StubRegistry.Reply(body: Data([0xFF, 0xFE]), headers: markdown), .unreadable),
            (StubRegistry.Reply(body: Data("x".utf8), nonHTTP: true), .unreadable),
        ]
        for (reply, expected) in cases {
            let api = StubbedAPI { _ in reply }
            await #expect(throws: expected) { try await importer(api).fetch(link(api)) }
        }
    }

    @Test func theDefaultImporterKeepsNoCookiesAndNoCache() {
        let configuration = SkillImporter().session.configuration
        #expect(configuration.urlCache == nil && !configuration.httpShouldSetCookies && configuration.httpCookieAcceptPolicy == .never)
    }
}
