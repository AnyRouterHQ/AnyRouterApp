import Foundation
import Testing

@testable import AnyRouter

struct ComposerMentionTests {
    private let exa = MentionItem(kind: .plugin(sourceID: "exa"), title: "Exa", trailing: "Plugin", icon: .asset("Logo-exa"))
    private let deepWiki = MentionItem(kind: .plugin(sourceID: "deepwiki"), title: "DeepWiki", trailing: "Plugin", icon: .symbol("books.vertical"))
    private let learn = MentionItem(kind: .plugin(sourceID: "mslearn"), title: "Microsoft Learn", trailing: "Plugin", icon: .symbol("x"))
    private let device = MentionItem(kind: .plugin(sourceID: "device"), title: "On this device", trailing: "Plugin", icon: .symbol("iphone"))

    private func file(_ name: String, kind: ChatAttachment.Kind = .text) -> ChatAttachment {
        ChatAttachment(id: UUID(), kind: kind, filename: name, utType: "public.plain-text", byteCount: 1, relativePath: "t/\(name)")
    }

    // MARK: Typing an @

    @Test func anAtThatStartsTheLastWordOpensTheList() {
        #expect(ComposerMention.query(in: "@") == "")
        #expect(ComposerMention.query(in: "@ex") == "ex")
        #expect(ComposerMention.query(in: "search with @Exa") == "Exa")
        #expect(ComposerMention.query(in: "line one\n@dee") == "dee")
    }

    @Test func anAddressOrAFinishedWordDoesNotOpenTheList() {
        #expect(ComposerMention.query(in: "mail me at me@example.com") == nil)
        #expect(ComposerMention.query(in: "@exa and more") == nil)
        #expect(ComposerMention.query(in: "@exa ") == nil)
        #expect(ComposerMention.query(in: "no at sign") == nil)
        #expect(ComposerMention.query(in: "") == nil)
    }

    // MARK: The rows

    @Test func pluginsComeFirstThenTheNewestFilesWithTheirKind() {
        let sources = [ToolSourceCatalog.device, ToolSourceCatalog.exa]
        let files = [file("old.txt"), file("scan.png", kind: .image)]
        let rows = ComposerMention.items(sources: sources, files: files)
        #expect(rows.map(\.title) == ["On this device", "Exa", "scan.png", "old.txt"])
        #expect(rows.map(\.trailing) == ["Plugin", "Plugin", "File", "File"])
        #expect(rows[1].icon == .asset("Logo-exa"))
        #expect(rows[2].icon == .symbol("photo"))
        #expect(rows[3].icon == .symbol("doc.text"))
    }

    @Test func atMostEightFilesAreOffered() {
        let files = (0..<12).map { file("f\($0).txt") }
        let rows = ComposerMention.items(sources: [], files: files)
        #expect(rows.count == ComposerMention.maxFiles)
        #expect(rows.first?.title == "f11.txt")
    }

    // MARK: Filtering

    @Test func anEmptyQueryKeepsEveryRow() {
        let all = [exa, deepWiki, learn]
        #expect(ComposerMention.filter(all, query: "") == all)
    }

    @Test func wordsThatStartWithTheQueryComeBeforeRowsThatOnlyContainIt() {
        let all = [exa, deepWiki, learn, device]
        #expect(ComposerMention.filter(all, query: "wi").map(\.title) == ["DeepWiki"])
        #expect(ComposerMention.filter(all, query: "learn").map(\.title) == ["Microsoft Learn"])
        // Only Exa has a word that starts with "e"; the others merely contain one.
        #expect(ComposerMention.filter(all, query: "e").map(\.title) == ["Exa", "DeepWiki", "Microsoft Learn", "On this device"])
        #expect(ComposerMention.filter(all, query: "zzz").isEmpty)
    }

    @Test func caseAndAccentsDoNotMatter() {
        let cafe = MentionItem(kind: .plugin(sourceID: "c"), title: "Café notes", trailing: "Plugin", icon: .symbol("x"))
        #expect(ComposerMention.filter([cafe, exa], query: "CAFE").map(\.title) == ["Café notes"])
        #expect(ComposerMention.filter([cafe, exa], query: "EXA").map(\.title) == ["Exa"])
    }

    // MARK: Choosing

    @Test func choosingTakesTheAtWordsOutOfTheText() {
        #expect(ComposerMention.removingQuery(from: "what is swift @ex") == "what is swift")
        #expect(ComposerMention.removingQuery(from: "@") == "")
        #expect(ComposerMention.removingQuery(from: "plain text") == "plain text")
        #expect(ComposerMention.removingQuery(from: "me@example.com") == "me@example.com")
    }

    @Test func aMentionTurnsOnItsOwnSourceAndAFileTurnsOnTheDevice() {
        let report = MentionItem(kind: .file(attachmentID: UUID(), filename: "report.txt"), title: "report.txt", trailing: "File", icon: .symbol("doc.text"))
        #expect(exa.forcedSourceID == "exa")
        #expect(report.forcedSourceID == "device")
        #expect(ComposerMention.forcedSourceIDs(of: [exa, deepWiki, report]) == ["exa", "deepwiki", "device"])
        #expect(ComposerMention.forcedSourceIDs(of: []).isEmpty)
    }

    @Test func theRequestTellsTheModelWhatWasAskedForAndTheSavedChatIsUntouched() {
        let report = MentionItem(kind: .file(attachmentID: UUID(), filename: "report.txt"), title: "report.txt", trailing: "File", icon: .symbol("doc.text"))
        let history = [
            ChatMessage(role: .user, content: "first"),
            ChatMessage(role: .assistant, content: "answer"),
            ChatMessage(role: .user, content: "what is swift"),
        ]
        let sent = ComposerMention.applying([exa, deepWiki, report], to: history)
        #expect(sent[0].content == "first")
        #expect(sent[1].content == "answer")
        #expect(sent[2].content == """
            what is swift

            Use the tools of Exa and DeepWiki to answer this message. Read "report.txt" with the read_attachment tool first.
            """)
        #expect(history[2].content == "what is swift")
        #expect(ComposerMention.applying([], to: history) == history)
        #expect(ComposerMention.applying([exa], to: []).isEmpty)
    }
}
