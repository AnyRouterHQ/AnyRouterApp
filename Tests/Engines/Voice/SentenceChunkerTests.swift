import Testing
@testable import AnyRouter

struct SentenceChunkerTests {
    private func chunks(_ pieces: [String], minimum: Int = 24) -> [String] {
        var chunker = SentenceChunker(minimumLength: minimum)
        var out: [String] = []
        for piece in pieces { out += chunker.push(piece) }
        return out + chunker.finish()
    }

    @Test func splitsEnglishAtSentenceEnds() {
        let text = "The sky is blue today. It will rain tomorrow afternoon. Bring a coat!"
        #expect(chunks([text]) == ["The sky is blue today.", "It will rain tomorrow afternoon.", "Bring a coat!"])
    }

    @Test func vietnameseUsesTheSameMarksAndKeepsDiacritics() {
        let text = "Xin chào bạn. Hôm nay trời đẹp quá, bạn có muốn đi dạo không? Tôi nghĩ là có!"
        #expect(chunks([text]) == ["Xin chào bạn.", "Hôm nay trời đẹp quá, bạn có muốn đi dạo không?", "Tôi nghĩ là có!"])
    }

    @Test func aReplyArrivingInSmallPiecesGivesTheSameSentencesAsTheWholeReply() {
        let text = "The sky is blue today. It will rain tomorrow afternoon. Bring a coat!"
        #expect(chunks(text.map(String.init)) == chunks([text]))
        let vietnamese = "Xin chào bạn. Hôm nay trời đẹp quá, bạn có muốn đi dạo không? Tôi nghĩ là có!"
        #expect(chunks(vietnamese.map(String.init)) == chunks([vietnamese]))
    }

    @Test func aStopAtTheEndOfTheTextSoFarWaitsInCaseItIsADecimal() {
        var chunker = SentenceChunker()
        #expect(chunker.push("Pi is about 3.") == [])
        #expect(chunker.push("14 and e is about 2.71. Both are irrational.") == ["Pi is about 3.14 and e is about 2.71."])
        #expect(chunker.finish() == ["Both are irrational."])
    }

    @Test func abbreviationsAndInitialsDoNotEndASentence() {
        #expect(chunks(["Tôi sống ở TP. Hồ Chí Minh từ năm 2010. Bạn thì sao?"])
            == ["Tôi sống ở TP. Hồ Chí Minh từ năm 2010.", "Bạn thì sao?"])
        #expect(chunks(["I met J. Smith yesterday at the old market."]) == ["I met J. Smith yesterday at the old market."])
        #expect(chunks(["Ask Dr. Lee about the results of the long test."]) == ["Ask Dr. Lee about the results of the long test."])
    }

    @Test func theFirstSentenceStartsSpeechAtOnceAndLaterShortOnesJoinTheNext() {
        #expect(chunks(["Yes. No. Maybe so, we will see what happens next."]) == ["Yes.", "No. Maybe so, we will see what happens next."])
    }

    @Test func codeBlocksAreNotRead() {
        let reply = "Here is code:\n```swift\nprint(1)\n```\nThat is all."
        #expect(chunks([reply]) == ["Here is code:", "That is all."])
        #expect(chunks(reply.map(String.init)) == ["Here is code:", "That is all."])
    }

    @Test func anOpenCodeBlockInAStreamingReplyStaysSilent() {
        var chunker = SentenceChunker()
        #expect(chunker.push("Here is code:\n```swift\nlet value = 1\n") == ["Here is code:"])
        #expect(chunker.push("print(value)\n") == [])
    }

    @Test func listItemsAreSpokenAsSentences() {
        #expect(chunks(["- first item\n- second item\n"]) == ["first item.", "second item."])
    }

    @Test func fullWidthStopsEndASentenceWithoutASpace() {
        #expect(chunks(["你好。今天天气很好！"]) == ["你好。", "今天天气很好！"])
    }

    @Test func aRunWithNoStopIsCutAtASpaceBeforeTheLimit() {
        let text = Array(repeating: "word", count: 75).joined(separator: " ")
        var chunker = SentenceChunker()
        let early = chunker.push(text)
        #expect(early.count == 1)
        #expect(early[0].count <= 221)
        let all = early + chunker.finish()
        #expect(all.joined(separator: " ").replacingOccurrences(of: ".", with: "") == text)
    }

    @Test func aLongRunIsCutAfterACommaWhenOneIsFarEnoughIn() {
        let text = String(repeating: "a", count: 80) + ", " + String(repeating: "b ", count: 100)
        var chunker = SentenceChunker()
        let early = chunker.push(text)
        #expect(early.first == String(repeating: "a", count: 80) + ",")
    }

    @Test func aRunWithNoSpaceIsCutAtTheLimit() {
        var chunker = SentenceChunker()
        let early = chunker.push(String(repeating: "x", count: 300))
        #expect(early.count == 1)
        #expect(early[0].count == 221)
    }

    @Test func textWithNothingToSayGivesNothing() {
        #expect(chunks(["...", " \n ", "—"]) == [])
    }
}
