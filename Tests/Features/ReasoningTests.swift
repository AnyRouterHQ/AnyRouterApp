import Foundation
import Testing
@testable import AnyRouter

struct ReasoningSplitterTests {
    /// Feeds the pieces and the end of the stream; returns everything that came out.
    private func run(_ pieces: [String]) -> ReasoningSplitter.Output {
        var splitter = ReasoningSplitter()
        var all = ReasoningSplitter.Output()
        for piece in pieces {
            let part = splitter.feed(piece)
            all.reasoning += part.reasoning
            all.text += part.text
        }
        let rest = splitter.finish()
        all.reasoning += rest.reasoning
        all.text += rest.text
        return all
    }

    @Test func aBlockAtTheStartIsReasoningAndTheRestIsTheAnswer() {
        #expect(run(["<think>plan</think>Answer"]) == .init(reasoning: "plan", text: "Answer"))
    }

    @Test func tagsCutAcrossPiecesNeverShowUpAsText() {
        let out = run(["<thi", "nk>ab", "c</th", "ink>\n\nHi"])
        #expect(out == .init(reasoning: "abc", text: "Hi"))
    }

    @Test func aTagCutAtEveryPositionGivesTheSameResult() {
        let whole = "<think>some thought</think>\nThe answer."
        for cut in 1..<whole.count {
            let index = whole.index(whole.startIndex, offsetBy: cut)
            let out = run([String(whole[..<index]), String(whole[index...])])
            #expect(out == .init(reasoning: "some thought", text: "The answer."), "cut at \(cut)")
        }
    }

    @Test func aBlockAfterTheFirstWordIsPartOfTheAnswer() {
        #expect(run(["Hello <think>x</think>"]) == .init(text: "Hello <think>x</think>"))
    }

    @Test func leadingWhitespaceBeforeTheTagIsAllowed() {
        #expect(run(["\n <think>x</think>y"]) == .init(reasoning: "x", text: "y"))
    }

    @Test func whitespaceBeforeTheFirstWordIsKeptWhenThereIsNoTag() {
        var splitter = ReasoningSplitter()
        #expect(splitter.feed("  ") == .init())
        #expect(splitter.feed("Hi") == .init(text: "  Hi"))
    }

    @Test func whitespaceBetweenTheBlockAndTheAnswerIsDroppedEvenWhenItArrivesAlone() {
        #expect(run(["<think>a</think>", "\n", "\n", "Hi"]) == .init(reasoning: "a", text: "Hi"))
    }

    @Test func anotherAngleBracketIsTextAtOnce() {
        #expect(run(["<b>bold</b>"]) == .init(text: "<b>bold</b>"))
    }

    @Test func aStreamThatEndsInsideAPartialOpeningTagKeepsItAsText() {
        #expect(run(["<th"]) == .init(text: "<th"))
    }

    @Test func aBlockThatNeverClosesStaysReasoning() {
        #expect(run(["<think>abc</thi"]) == .init(reasoning: "abc</thi"))
    }
}

struct ReasoningRecorderTests {
    @Test func nothingIsRecordedUntilReasoningArrives() {
        var recorder = ReasoningRecorder()
        recorder.add("", at: 1)
        recorder.end(at: 2)
        #expect(recorder.trace == nil)
        #expect(!recorder.hasEnded)
    }

    @Test func theDurationRunsFromTheFirstWordToTheFirstEnd() {
        var recorder = ReasoningRecorder()
        recorder.add("a", at: 10)
        #expect(recorder.trace == ReasoningTrace(text: "a", durationMs: nil))
        recorder.add("b", at: 11)
        recorder.end(at: 22.4)
        recorder.end(at: 99)
        #expect(recorder.trace == ReasoningTrace(text: "ab", durationMs: 12_400))
        #expect(recorder.hasEnded)
    }

    @Test func aClockThatWentBackNeverGivesANegativeTime() {
        var recorder = ReasoningRecorder()
        recorder.add("a", at: 10)
        recorder.end(at: 5)
        #expect(recorder.trace?.durationMs == 0)
    }
}

struct ReasoningLogicTests {
    @Test func theTitleSaysThinkingWhileItWritesAndTheTimeAfter() {
        #expect(ReasoningLogic.title(durationMs: nil, isStreaming: true) == "Thinking…")
        #expect(ReasoningLogic.title(durationMs: 12_000, isStreaming: false) == "Thought for 12s")
        #expect(ReasoningLogic.title(durationMs: nil, isStreaming: false) == "Thought")
    }

    @Test(arguments: [(0, "1s"), (400, "1s"), (1_499, "1s"), (12_000, "12s"), (59_400, "59s"), (60_000, "1m"), (125_000, "2m 5s")])
    func durationsReadInSecondsThenMinutes(ms: Int, text: String) {
        #expect(ReasoningLogic.duration(ms) == text)
    }

    @Test func theLatestLineIsTheLastOneWithWords() {
        #expect(ReasoningLogic.latestLine("") == nil)
        #expect(ReasoningLogic.latestLine("  \n\n") == nil)
        #expect(ReasoningLogic.latestLine("first\n  second thought  \n\n") == "second thought")
    }

    @Test func aLongLineIsCutToOne() {
        let line = String(repeating: "word ", count: 40)
        let cut = ReasoningLogic.latestLine(line, limit: 20)
        #expect(cut == "word word word word…")
    }
}

struct ReplyPartsTests {
    private let steps = [ToolStep(call: ToolCall(id: "1", name: "web_search", argumentsJSON: "{}"), result: nil)]

    @Test func partsComeInTheOrderThoughtToolsAnswer() {
        let thought = ReasoningTrace(text: "hm", durationMs: 4_000)
        let parts = ReplyParts.make(reasoning: thought, steps: steps, content: "Answer", isStreaming: false)
        #expect(parts.map(\.id) == ["reasoning", "tools", "text"])
        #expect(parts.first == .reasoning(thought, isStreaming: false))
    }

    @Test func emptyPartsAreLeftOut() {
        #expect(ReplyParts.make(reasoning: nil, steps: [], content: "", isStreaming: true).isEmpty)
        #expect(ReplyParts.make(reasoning: nil, steps: [], content: "Hi", isStreaming: false) == [.text("Hi")])
    }

    @Test func theModelIsThinkingWhileTheReplyStreamsAndTheThoughtHasNoEnd() {
        let open = ReasoningTrace(text: "hm", durationMs: nil)
        let closed = ReasoningTrace(text: "hm", durationMs: 1_000)
        #expect(ReplyParts.make(reasoning: open, steps: [], content: "", isStreaming: true) == [.reasoning(open, isStreaming: true)])
        #expect(ReplyParts.make(reasoning: closed, steps: [], content: "", isStreaming: true) == [.reasoning(closed, isStreaming: false)])
        #expect(ReplyParts.make(reasoning: open, steps: [], content: "", isStreaming: false) == [.reasoning(open, isStreaming: false)],
                "a stopped reply is not still thinking")
    }
}

struct ReasoningRecordTests {
    @Test func theReasoningIsKeptWithTheReply() {
        let record = MessageRecord(role: .assistant, content: "x")
        #expect(record.reasoning == nil)
        record.reasoning = ReasoningTrace(text: "thinking", durationMs: 2_000)
        #expect(record.reasoning == ReasoningTrace(text: "thinking", durationMs: 2_000))
        record.reasoning = nil
        #expect(record.reasoningData == nil)
    }

    @Test func unreadableDataReadsAsNoReasoning() {
        let record = MessageRecord(role: .assistant, content: "x")
        record.reasoningData = Data("not json".utf8)
        #expect(record.reasoning == nil)
    }
}
