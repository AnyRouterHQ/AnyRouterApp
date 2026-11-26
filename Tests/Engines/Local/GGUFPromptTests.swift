import Foundation
import Testing
@testable import AnyRouter

struct PromptBuilderTests {
    private func chat(_ role: ChatMessage.Role, _ text: String) -> ChatMessage {
        ChatMessage(role: role, content: text)
    }

    @Test func systemPromptComesFirstWhenTheChatHasNone() {
        let result = PromptBuilder.promptMessages(from: [chat(.user, "hi")], systemPrompt: "Be brief.")
        #expect(result == [PromptMessage(role: "system", content: "Be brief."), PromptMessage(role: "user", content: "hi")])
    }

    @Test func anExistingSystemMessageWinsOverTheParamsPrompt() {
        let result = PromptBuilder.promptMessages(
            from: [chat(.system, "From thread"), chat(.user, "hi")], systemPrompt: "From params")
        #expect(result.map(\.content) == ["From thread", "hi"])
    }

    @Test func emptyOrMissingSystemPromptAddsNothing() {
        #expect(PromptBuilder.promptMessages(from: [chat(.user, "hi")], systemPrompt: nil).count == 1)
        #expect(PromptBuilder.promptMessages(from: [chat(.user, "hi")], systemPrompt: "").count == 1)
    }

    private let history = [
        PromptMessage(role: "system", content: "sys"),
        PromptMessage(role: "user", content: "u1"),
        PromptMessage(role: "assistant", content: "a1"),
        PromptMessage(role: "user", content: "u2"),
        PromptMessage(role: "assistant", content: "a2"),
        PromptMessage(role: "user", content: "u3"),
    ]

    @Test func nothingIsDroppedWhenTheChatFits() {
        #expect(PromptBuilder.trimmed(history) { _ in true } == history)
    }

    @Test func theOldestTurnsGoFirstAndTheSystemMessageAndLastMessageStay() {
        let result = PromptBuilder.trimmed(history) { $0.count <= 4 }
        #expect(result?.first?.role == "system")
        #expect(result?.last?.content == "u3")
        #expect(result?.map(\.content) == ["sys", "u2", "a2", "u3"])
    }

    @Test func aLastMessageThatNeverFitsIsReportedNotTruncated() {
        #expect(PromptBuilder.trimmed(history) { _ in false } == nil)
    }

    @Test func trimmingPropagatesErrorsFromTheMeasure() {
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            _ = try PromptBuilder.trimmed(history) { _ in throw Boom() }
        }
    }

    @Test func chatMLFallbackOpensAnAssistantTurn() {
        let text = ChatMLFormatter.format([
            PromptMessage(role: "system", content: "S"), PromptMessage(role: "user", content: "U"),
        ])
        #expect(text == "<|im_start|>system\nS<|im_end|>\n<|im_start|>user\nU<|im_end|>\n<|im_start|>assistant\n")
    }
}

struct JinjaChatTemplateTests {
    // Real newlines in the template text, as in a GGUF file: a raw string would put a backslash and an n in the output.
    private let chatML = "{% for m in messages %}<|im_start|>{{ m.role }}\n{{ m.content }}<|im_end|>\n{% endfor %}{% if add_generation_prompt %}<|im_start|>assistant\n{% endif %}"

    @Test func aTemplateRendersTheConversationAndOpensTheReply() throws {
        let template = try #require(JinjaChatTemplate(source: chatML))
        let text = template.render(
            [PromptMessage(role: "system", content: "Be brief."), PromptMessage(role: "user", content: "hi")], bos: nil, eos: nil)
        #expect(text == "<|im_start|>system\nBe brief.<|im_end|>\n<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n")
    }

    @Test func theTemplateSeesTheSpecialTokensAndKnowsThinkingIsOff() throws {
        let source = #"{{ bos_token }}{% for m in messages %}[{{ m.role }}]{{ m.content }}{{ eos_token }}{% endfor %}{% if enable_thinking %}T{% else %}N{% endif %}"#
        let template = try #require(JinjaChatTemplate(source: source))
        #expect(template.render([PromptMessage(role: "user", content: "x")], bos: "<s>", eos: "</s>") == "<s>[user]x</s>N")
        #expect(template.render([PromptMessage(role: "user", content: "x")], bos: nil, eos: nil) == "[user]xN", "no BOS renders as nothing")
    }

    @Test func aTemplateThatFailsOrRendersNothingGivesNilSoTheNextFormatterRuns() throws {
        let failing = try #require(JinjaChatTemplate(source: #"{{ raise_exception("no system role") }}"#))
        #expect(failing.render([PromptMessage(role: "user", content: "x")], bos: nil, eos: nil) == nil)
        let empty = try #require(JinjaChatTemplate(source: ""))
        #expect(empty.render([PromptMessage(role: "user", content: "x")], bos: nil, eos: nil) == nil)
    }

    @Test func syntaxTheEngineCannotCompileGivesNoTemplate() {
        #expect(JinjaChatTemplate(source: "{% for m in messages %}") == nil)
    }
}

struct SpecialTokenTests {
    @Test func aPromptThatAlreadyStartsWithBOSDoesNotGetASecondOne() {
        #expect(!PromptBuilder.addsSpecialTokens(to: "<|begin_of_text|><|start_header_id|>user", bosText: "<|begin_of_text|>"))
    }

    @Test func aPromptWithoutBOSGetsTheVocabularysOwn() {
        #expect(PromptBuilder.addsSpecialTokens(to: "<|turn>user\nhi<turn|>\n", bosText: "<bos>"))
        #expect(PromptBuilder.addsSpecialTokens(to: "<|im_start|>user", bosText: nil))
        #expect(PromptBuilder.addsSpecialTokens(to: "hi", bosText: ""))
    }

    @Test func bosInTheMiddleOfAPromptIsNotTheStart() {
        #expect(PromptBuilder.addsSpecialTokens(to: "hello <bos>", bosText: "<bos>"))
    }
}

struct Gemma4FormatterTests {
    @Test func recognizesTheGemma4TemplateByItsTurnMarkers() {
        #expect(Gemma4Formatter.matches(template: "{{ '<|turn>' + role }}...{{ '<turn|>\\n' }}"))
        #expect(!Gemma4Formatter.matches(template: "<start_of_turn>user\n<end_of_turn>"))
        #expect(!Gemma4Formatter.matches(template: "<|im_start|>user<|im_end|>"))
    }

    @Test func aSingleUserTurnEndsOpenOnTheModelTurn() {
        let text = Gemma4Formatter.format([PromptMessage(role: "user", content: "What is 2+2?")])
        #expect(text == "<|turn>user\nWhat is 2+2?<turn|>\n<|turn>model\n")
    }

    @Test func systemAndHistoryKeepTheirTurnsAndAssistantBecomesModel() {
        let text = Gemma4Formatter.format([
            PromptMessage(role: "system", content: "Be brief."),
            PromptMessage(role: "user", content: "hi"),
            PromptMessage(role: "assistant", content: "Hello!"),
            PromptMessage(role: "user", content: "bye"),
        ])
        #expect(text == "<|turn>system\nBe brief.<turn|>\n<|turn>user\nhi<turn|>\n<|turn>model\nHello!<turn|>\n<|turn>user\nbye<turn|>\n<|turn>model\n")
    }

    @Test func messageTextIsTrimmedLikeTheTemplateDoes() {
        let text = Gemma4Formatter.format([PromptMessage(role: "user", content: "  hi\n\n")])
        #expect(text == "<|turn>user\nhi<turn|>\n<|turn>model\n")
    }

    @Test func theFormatCarriesNoBosBecauseTokenizingAddsIt() {
        #expect(!Gemma4Formatter.format([PromptMessage(role: "user", content: "x")]).contains("<bos>"))
    }
}

struct ThoughtChannelFilterTests {
    @Test func tokensInsideTheChannelAndItsMarkersAreHidden() {
        var filter = ThoughtChannelFilter(open: 100, close: 101)
        let visible = [5, 100, 7, 8, 101, 9].filter { filter.isVisible(Int32($0)) }
        #expect(visible == [5, 9])
    }

    @Test func anUnclosedChannelHidesTheRest() {
        var filter = ThoughtChannelFilter(open: 100, close: 101)
        let visible = [100, 7, 8].filter { filter.isVisible(Int32($0)) }
        #expect(visible.isEmpty)
    }

    @Test func modelsWithoutChannelTokensShowEverything() {
        var filter = ThoughtChannelFilter(open: nil, close: nil)
        #expect([1, 100, 101].allSatisfy { filter.isVisible(Int32($0)) })
    }
}

struct UTF8AccumulatorTests {
    @Test func plainASCIIPassesStraightThrough() {
        var acc = UTF8Accumulator()
        #expect(acc.append(Array("Hello".utf8)) == "Hello")
        #expect(acc.flush() == nil)
    }

    @Test func aCharacterSplitAcrossTokensIsHeldBackUntilItIsComplete() {
        let bytes = Array("a\u{1F600}b".utf8) // a, 4-byte emoji, b
        var acc = UTF8Accumulator()
        #expect(acc.append(Array(bytes[0..<2])) == "a")
        #expect(acc.append(Array(bytes[2..<4])) == nil)
        #expect(acc.append(Array(bytes[4..<5])) == "\u{1F600}")
        #expect(acc.append(Array(bytes[5..<6])) == "b")
    }

    @Test func aTwoByteCharacterSplitInHalf() {
        let bytes = Array("\u{00E9}".utf8)
        var acc = UTF8Accumulator()
        #expect(acc.append([bytes[0]]) == nil)
        #expect(acc.append([bytes[1]]) == "\u{00E9}")
    }

    @Test func flushReleasesAnUnfinishedTailLossily() {
        var acc = UTF8Accumulator()
        #expect(acc.append([0xF0, 0x9F]) == nil)
        #expect(acc.flush() == "\u{FFFD}")
        #expect(acc.flush() == nil)
    }

    @Test func invalidBytesInTheMiddleDoNotStallTheStream() {
        var acc = UTF8Accumulator()
        #expect(acc.append([0x68, 0xFF, 0x69]) == "h\u{FFFD}i")
    }

    @Test func emptyInputGivesNothing() {
        var acc = UTF8Accumulator()
        #expect(acc.append([]) == nil)
    }
}
