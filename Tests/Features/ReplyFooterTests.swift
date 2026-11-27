import Foundation
import Testing
@testable import AnyRouter

struct ReplyFooterTests {
    // MARK: Fixtures

    private func search(_ pages: [(title: String, url: String)], name: String = "web_search_exa", id: String = "s1") -> ToolStep {
        let text = pages.map { "Title: \($0.title)\nURL: \($0.url)\nHighlights:\nsome text" }.joined(separator: "\n\n")
        let call = ToolCall(id: id, name: name, argumentsJSON: #"{"query":"q"}"#)
        return ToolStep(call: call, result: ToolResult(callID: id, name: name, text: text, isError: false))
    }

    private func make(
        content: String = "An answer.", streaming: Bool = false, regenerate: Bool = false, details: Bool = true,
        name: String? = nil, id: String? = nil, metadata: ResponseMetadata? = nil, steps: [ToolStep] = []
    ) -> ReplyFooter? {
        ReplyFooter.make(
            content: content, isStreaming: streaming, showsRegenerate: regenerate, showsDetails: details,
            requestedName: name, requestedID: id, metadata: metadata, steps: steps)
    }

    private func timed() -> ResponseMetadata {
        var value = ResponseMetadata()
        value.totalMs = 2100
        return value
    }

    // MARK: Visibility and order

    @Test func noFooterWhileTheReplyIsStillWritten() {
        #expect(make(streaming: true) == nil)
    }

    @Test func noFooterForAnEmptyReply() {
        #expect(make(content: "") == nil)
    }

    @Test func theRowHasCopyAndShareAndReadAloudLeaveIt() throws {
        let footer = try #require(make())
        #expect(footer.actions == [.copy])
    }

    @Test func regenerateComesLastAndOnlyWhenOffered() throws {
        let footer = try #require(make(regenerate: true))
        #expect(footer.actions == [.copy, .regenerate])
    }

    // MARK: Model label

    @Test func theLabelNamesTheModelThatServedTheReplyBehindARouter() throws {
        var metadata = ResponseMetadata()
        metadata.servedModelName = "Nemotron 3.5 Bolt E4B"
        let footer = try #require(make(name: "AnyRouter", id: ModelDescriptor.autoRouterID, metadata: metadata))
        #expect(footer.modelLabel == "Nemotron 3.5")
    }

    @Test func theLabelFallsBackToTheRequestedName() throws {
        let f1 = try #require(make(name: "Claude Haiku 4.5"))
        #expect(f1.modelLabel == "Haiku 4.5")
    }

    @Test func theLabelFallsBackToANameMadeFromTheServedId() throws {
        var metadata = ResponseMetadata()
        metadata.servedModelID = "nvidia/nemotron-3.5-bolt-e4b"
        let f2 = try #require(make(metadata: metadata))
        #expect(f2.modelLabel == "Nemotron 3.5")
    }

    @Test func theLabelFallsBackToANameMadeFromTheRequestedId() throws {
        let f3 = try #require(make(id: "openai/gpt-6.2-sol"))
        #expect(f3.modelLabel == "Gpt 6.2 Sol")
    }

    @Test func noNameAnywhereMeansNoLabel() throws {
        let f4 = try #require(make())
        #expect(f4.modelLabel == nil)
        let f5 = try #require(make(name: ""))
        #expect(f5.modelLabel == nil)
    }

    // MARK: The line

    private func meta(
        cost: String? = nil, completion: Int? = nil, ttft: Int? = nil, total: Int? = nil
    ) -> ResponseMetadata {
        var value = ResponseMetadata()
        value.costUSD = cost.flatMap { Decimal(string: $0) }
        value.completionTokens = completion
        value.ttftMs = ttft
        value.totalMs = total
        return value
    }

    @Test func aPaidReplyReadsModelPriceAndSpeed() throws {
        let metadata = meta(cost: "0.0012", completion: 84, ttft: 400, total: 2400)
        let footer = try #require(make(name: "Claude Haiku 4.5", metadata: metadata))
        #expect(footer.summary.parts == ["Haiku 4.5", "$0.0012", "42 tok/s"])
        #expect(footer.summary.line == "Haiku 4.5 · $0.0012 · 42 tok/s")
    }

    @Test func aFreeReplyShowsNoPrice() throws {
        let metadata = meta(cost: "0", completion: 84, ttft: 400, total: 2400)
        let footer = try #require(make(name: "Nemotron 3.5 Bolt E4B", metadata: metadata))
        #expect(footer.summary.price == nil)
        #expect(footer.summary.line == "Nemotron 3.5 · 42 tok/s")
    }

    @Test func aLocalOrAppleReplyShowsNoPrice() throws {
        // Local and Apple models are stored with cost 0 and provider "On device" (ChatViewModel.finalMetadata).
        var local = meta(cost: "0", completion: 40, ttft: 500, total: 1500)
        local.provider = "On device"
        let footer = try #require(make(name: "Apple Intelligence", id: "apple/foundation", metadata: local))
        #expect(footer.summary.line == "Apple · 40 tok/s")
    }

    @Test func aMissingCostOrSpeedLeavesThePartOut() throws {
        let noSpeed = try #require(make(name: "Claude Haiku 4.5", metadata: meta(cost: "0.5")))
        #expect(noSpeed.summary.parts == ["Haiku 4.5", "$0.50"])
        let nothing = try #require(make(name: "Claude Haiku 4.5", metadata: ResponseMetadata()))
        #expect(nothing.summary.parts == ["Haiku 4.5"])
    }

    @Test func withoutAModelNameThePriceStandsAlone() throws {
        let footer = try #require(make(metadata: meta(cost: "0.5")))
        #expect(footer.summary.line == "$0.50")
    }

    @Test func noNameAndNoMetadataMeansNoLine() throws {
        let footer = try #require(make())
        #expect(footer.summary.parts.isEmpty)
        #expect(footer.summary.line == nil)
    }

    @Test func speedIsRoundedToWholeTokensPerSecond() {
        #expect(ResponseFormat.speed(41.6) == "42 tok/s")
        #expect(ResponseFormat.speed(7.2) == "7 tok/s")
    }

    @Test func withTheSettingOffOnlyTheNameStaysAndNothingOpens() throws {
        let metadata = meta(cost: "0.0012", completion: 84, ttft: 400, total: 2400)
        let footer = try #require(make(details: false, name: "Claude Haiku 4.5", metadata: metadata))
        #expect(footer.summary.line == "Haiku 4.5")
        #expect(footer.details == nil)
        #expect(!footer.hasDetails)
        let bare = try #require(make(details: false, name: "Claude Haiku 4.5"))
        #expect(bare.summary.line == "Haiku 4.5")
    }

    @Test func theSheetOpensWhenSomethingIsStored() throws {
        #expect(try #require(make(metadata: timed())).hasDetails)
        #expect(try #require(make()).hasDetails == false)
        #expect(try #require(make(metadata: ResponseMetadata())).hasDetails == false)
        let call = ToolCall(id: "c", name: "calculator", argumentsJSON: "{}")
        let step = ToolStep(call: call, result: ToolResult(callID: "c", name: "calculator", text: "2", isError: false))
        #expect(try #require(make(steps: [step])).hasDetails, "tool calls alone are worth a sheet")
    }

    // MARK: Sources

    @Test func sourcesFollowTheOrderOfTheCallsAndOfTheResults() throws {
        let first = search([("One", "https://a.example.com/1"), ("Two", "https://b.example.com/2")], id: "s1")
        let second = search([("Three", "https://c.example.com/3")], name: "web_search", id: "s2")
        let footer = try #require(make(steps: [first, second]))
        #expect(footer.sources.map(\.title) == ["One", "Two", "Three"])
    }

    @Test func theSamePageWrittenTwoWaysCountsOnce() throws {
        let step = search([
            ("A", "https://www.example.com/post"), ("A again", "https://example.com/post/"),
            ("A shouting host", "https://EXAMPLE.com/post"), ("Other query", "https://example.com/post?page=2"),
        ])
        let footer = try #require(make(steps: [step]))
        #expect(footer.sources.map(\.title) == ["A", "Other query"])
    }

    @Test func aPageFoundByTwoSearchesKeepsItsFirstPlace() throws {
        let one = search([("First", "https://a.example.com/x"), ("Shared", "https://s.example.com/x")], id: "s1")
        let two = search([("Shared again", "https://s.example.com/x"), ("Last", "https://z.example.com/x")], id: "s2")
        let footer = try #require(make(steps: [one, two]))
        #expect(footer.sources.map(\.title) == ["First", "Shared", "Last"])
    }

    @Test func aFailedOrUnfinishedCallAddsNothing() throws {
        let failed = ToolStep(
            call: ToolCall(id: "f", name: "web_search", argumentsJSON: "{}"),
            result: ToolResult(callID: "f", name: "web_search", text: "Title: T\nURL: https://a.example.com", isError: true))
        let running = ToolStep(call: ToolCall(id: "r", name: "web_search", argumentsJSON: "{}"), result: nil)
        let footer = try #require(make(steps: [failed, running]))
        #expect(footer.sources.isEmpty)
    }

    @Test func aPageThatWasOpenedIsASourceTitledByItsHost() throws {
        let call = ToolCall(id: "p", name: "fetch_url", argumentsJSON: #"{"url":"https://www.docs.example.com/guide"}"#)
        let step = ToolStep(call: call, result: ToolResult(callID: "p", name: "fetch_url", text: "page text", isError: false))
        let source = try #require(make(steps: [step])).sources.first
        #expect(source?.title == "docs.example.com")
        #expect(source?.host == "docs.example.com")
    }

    @Test func aFetchWithoutAUsableAddressAddsNothing() throws {
        func fetch(_ arguments: String) -> ToolStep {
            let call = ToolCall(id: "p", name: "fetch_url", argumentsJSON: arguments)
            return ToolStep(call: call, result: ToolResult(callID: "p", name: "fetch_url", text: "text", isError: false))
        }
        let steps = [fetch("not json"), fetch(#"{"other":"x"}"#), fetch(#"{"url":"ftp://files.example.com/a"}"#)]
        let footer = try #require(make(steps: steps))
        #expect(footer.sources.isEmpty)
    }

    @Test func otherToolsAreNotSources() throws {
        let call = ToolCall(id: "c", name: "calculator", argumentsJSON: #"{"expression":"1+1"}"#)
        let step = ToolStep(call: call, result: ToolResult(callID: "c", name: "calculator", text: "2", isError: false))
        let footer = try #require(make(steps: [step]))
        #expect(footer.sources.isEmpty)
    }

    @Test func resultsWithoutARealWebAddressAreDropped() throws {
        let step = search([
            ("Mail", "mailto:someone@example.com"), ("Host missing", "https:///path"), ("Spaces", "not a url"),
            ("Good", "http://plain.example.com/a"),
        ])
        let footer = try #require(make(steps: [step]))
        #expect(footer.sources.map(\.title) == ["Good"])
    }

    // MARK: One source

    @Test func aSourceReadsLikeAPersonWouldWriteIt() throws {
        let source = try #require(ReplyFooter.Source(title: "", link: "http://WWW.Example.COM/a/b?x=1"))
        #expect(source.host == "example.com")
        #expect(source.title == "example.com", "an untitled page is named by its site")
        #expect(source.id == "example.com/a/b?x=1")
    }

    @Test func theIconIsAskedFromTheSiteItselfOverHttps() throws {
        let source = try #require(ReplyFooter.Source(title: "T", link: "http://news.example.com/story"))
        #expect(source.faviconURL.absoluteString == "https://news.example.com/favicon.ico")
    }

    // MARK: The chain and the count

    @Test func theChainShowsThreeDistinctSitesInOrder() throws {
        let step = search([
            ("1", "https://a.example.com/1"), ("2", "https://a.example.com/2"), ("3", "https://b.example.com/1"),
            ("4", "https://c.example.com/1"), ("5", "https://d.example.com/1"),
        ])
        let footer = try #require(make(steps: [step]))
        #expect(footer.sources.count == 5)
        #expect(footer.faviconSources.map(\.host) == ["a.example.com", "b.example.com", "c.example.com"])
        #expect(footer.faviconSources.count == ReplyFooter.maxFavicons)
    }

    @Test func theCountIsSingularForOneAndEmptyForNone() throws {
        let f10 = try #require(make())
        #expect(f10.sourcesLabel == nil)
        let one = search([("1", "https://a.example.com/1")])
        let f11 = try #require(make(steps: [one]))
        #expect(f11.sourcesLabel == "1 source")
        let two = search([("1", "https://a.example.com/1"), ("2", "https://b.example.com/1")])
        let f12 = try #require(make(steps: [two]))
        #expect(f12.sourcesLabel == "2 sources")
    }
}
