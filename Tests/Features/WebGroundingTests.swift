import Foundation
import Testing

@testable import AnyRouter

private final class GroundingFixtureAnchor {}

struct WebGroundingTests {
    // MARK: Does the message need the web

    @Test func questionsAboutNowAndSearchRequestsNeedTheWeb() {
        let needs = [
            "What's the latest news about Swift 7?",
            "bitcoin price today",
            "Search for the best ramen in Tokyo",
            "search ramen near me please",
            "What happened in 2026?",
            "weather in Hanoi tomorrow",
            "Look up the release date of the next iPhone",
            "who won the election",
            "Can you google that for me",
            "How much is a flight to Paris this week?",
        ]
        for text in needs { #expect(WebGrounding.needsFreshInfo(text), "\(text)") }
    }

    @Test func questionsTheModelCanAnswerFromWhatItKnowsDoNot() {
        let doesNot = [
            "Write a poem about spring",
            "Explain how recursion works",
            "Translate good morning to French",
            "What is 12 times 7?",
            "hi",
            "How do I reverse a string in Swift?",
            "What did people eat in 1850?",
            "Why is the sky blue and the sea too",
        ]
        for text in doesNot { #expect(!WebGrounding.needsFreshInfo(text), "\(text)") }
    }

    @Test func codeAndLongPastedTextAreNeverSent() {
        #expect(!WebGrounding.needsFreshInfo("latest version?\n```swift\nlet x = 1\n```"))
        let pasted = "Summarize this: " + String(repeating: "the latest news today ", count: 40)
        #expect(pasted.count > WebGrounding.maxMessageCharacters)
        #expect(!WebGrounding.needsFreshInfo(pasted))
        #expect(!WebGrounding.needsFreshInfo("   short   "))
    }

    @Test func wordsAreMatchedWholeAndPunctuationAndCaseDoNotMatter() {
        #expect(WebGrounding.needsFreshInfo("LATEST!!! iOS version???"))
        #expect(WebGrounding.needsFreshInfo("what\u{2019}s new in Xcode"))
        #expect(!WebGrounding.needsFreshInfo("Tell me about the newsroom layout"), "newsroom is not news")
        #expect(!WebGrounding.needsFreshInfo("Explain the stockholm syndrome"), "stockholm is not stock")
        #expect(!WebGrounding.needsFreshInfo("Describe the year 2019 for me"), "only years from 2024 on")
    }

    @Test func theQueryIsOneLineAndShort() {
        #expect(WebGrounding.query(from: "  latest\n  swift   news ") == "latest swift news")
        #expect(WebGrounding.query(from: String(repeating: "a", count: 900)).count == WebGrounding.maxQueryCharacters)
    }

    @Test func onlyModelsWithoutAToolLoopGetASearchRunForThem() {
        #expect(WebGrounding.appliesTo(.gguf))
        #expect(WebGrounding.appliesTo(.mlx))
        #expect(!WebGrounding.appliesTo(.apple))
        #expect(!WebGrounding.appliesTo(.anyrouter))
    }

    // MARK: Reading Exa's answer

    @Test func theRecordedExaAnswerGivesTitleUrlAndACappedSnippet() throws {
        let url = try #require(Bundle(for: GroundingFixtureAnchor.self).url(forResource: "exa-search", withExtension: "txt"))
        let raw = try String(contentsOf: url, encoding: .utf8)
        let data = try #require(raw.split(separator: "\n").first { $0.hasPrefix("data:") })
        let message = try #require(JSONValue.parse(String(data.dropFirst(5))))
        let text = try #require(message["result"]?["content"]?.array?.first?["text"]?.string)

        let sources = WebGrounding.parse(text)
        #expect(sources.count == 2)
        #expect(sources[0].title == "Swift Programming Language")
        #expect(sources[0].url == "https://www.swift.org/")
        #expect(sources[0].snippet.hasPrefix("Swift Programming Language # Swift is the powerful"))
        #expect(sources[0].snippet.count <= WebGrounding.snippetCharacters + 1)
        #expect(sources[0].snippet.hasSuffix("…"))
        #expect(!sources[0].snippet.contains("\n"))
        #expect(!sources[0].snippet.contains("..."))
    }

    @Test func parsingSkipsAnEntryWithoutAnAddressAndTheCutMarker() {
        let text = """
            Title: One
            URL: https://one.example/
            Published: N/A
            Highlights:
            first line

            ...

            second line
            [Result cut at 6000 characters.]
            """
        let sources = WebGrounding.parse(text + "\nTitle: No address\nHighlights:\nnothing")
        #expect(sources == [WebGrounding.Source(title: "One", url: "https://one.example/", snippet: "first line second line")])
        #expect(WebGrounding.parse("no results here").isEmpty)
        #expect(WebGrounding.parse("").isEmpty)
    }

    // MARK: Context

    @Test func theContextHoldsTheTopThreeWithACitationInstruction() throws {
        let sources = (1...5).map { WebGrounding.Source(title: "Title \($0)", url: "https://e.example/\($0)", snippet: "snippet \($0)") }
        let context = try #require(WebGrounding.context(for: sources))
        #expect(context.hasPrefix("Web search results, fetched just now."))
        #expect(context.contains("cite a source as [1], [2] or [3]"))
        #expect(context.contains("[1] Title 1\nhttps://e.example/1\nsnippet 1"))
        #expect(context.contains("[3] Title 3\nhttps://e.example/3\nsnippet 3"))
        #expect(!context.contains("Title 4"))
        #expect(WebGrounding.context(for: []) == nil)
    }

    @Test func theContextStaysSmallEnoughForASmallModel() throws {
        let long = String(repeating: "word ", count: 400)
        let sources = WebGrounding.parse((1...3).map { "Title: T\($0)\nURL: https://e.example/\($0)\nHighlights:\n" + long }.joined(separator: "\n"))
        let context = try #require(WebGrounding.context(for: sources))
        #expect(context.count < 2_200)
    }

    @Test func theResultsGoInFrontOfTheLastQuestionOnly() {
        let history = [
            ChatMessage(role: .user, content: "first"),
            ChatMessage(role: .assistant, content: "answer"),
            ChatMessage(role: .user, content: "latest news?"),
        ]
        let sent = WebGrounding.applying("CONTEXT", to: history)
        #expect(sent[0].content == "first")
        #expect(sent[2].content == "CONTEXT\n\nQuestion: latest news?")
        #expect(history[2].content == "latest news?")
        #expect(WebGrounding.applying("CONTEXT", to: []).isEmpty)
    }
}
