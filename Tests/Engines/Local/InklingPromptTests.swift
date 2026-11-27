import Foundation
import Testing
@testable import AnyRouter

/// Inkling 2 writes messages as special-token spans. The prompt must match its chat template, and its reasoning span
/// must reach the reasoning row as a `<think>` block.
struct InklingPromptTests {
    @Test func theTemplateIsRecognizedByItsMessageTokens() {
        #expect(InklingFormatter.matches(template: "{{ '<|message_model|>' }}{{ '<|content_text|>' }}"))
        #expect(!InklingFormatter.matches(template: "<|im_start|>assistant"))
    }

    @Test func aChatIsWrittenAsTheTemplateWritesIt() {
        let prompt = InklingFormatter.format([
            PromptMessage(role: "system", content: "Be brief."),
            PromptMessage(role: "user", content: "Hi"),
            PromptMessage(role: "assistant", content: "Hello."),
            PromptMessage(role: "user", content: "2+2?"),
        ])
        #expect(prompt == "<|message_system|><|content_text|>Be brief.<|end_message|>"
            + "<|message_system|><|content_text|>Thinking effort level: 0.2<|end_message|>"
            + "<|message_user|><|content_text|>Hi<|end_message|>"
            + "<|message_model|><|content_text|>Hello.<|end_message|><|content_model_end_sampling|>"
            + "<|message_user|><|content_text|>2+2?<|end_message|>")
    }

    @Test func aChatOfOnlySystemMessagesStillEndsWithTheEffortLine() {
        #expect(InklingFormatter.format([PromptMessage(role: "system", content: "S")])
            == "<|message_system|><|content_text|>S<|end_message|><|message_system|><|content_text|>Thinking effort level: 0.2<|end_message|>")
    }

    @Test func theReasoningSpanBecomesAThinkBlockTheSplitterReads() {
        var tagger = ThinkingSpanTagger(open: 8, close: 10)
        // <|message_model|> <|content_thinking|> "Two plus two." <|end_message|> <|message_model|> <|content_text|> "4" <|end_message|>
        let tokens: [(Int32, String)] = [(1, ""), (8, ""), (100, "Two plus two."), (10, ""), (1, ""), (4, ""), (101, "4"), (10, "")]
        var text = ""
        for (token, piece) in tokens { text += tagger.tag(for: token) ?? piece }
        #expect(text == "<think>Two plus two.</think>4", "a close token outside the span is not a tag")
        var splitter = ReasoningSplitter()
        var output = splitter.feed(text)
        let tail = splitter.finish()
        output.reasoning += tail.reasoning
        output.text += tail.text
        #expect(output.reasoning == "Two plus two.")
        #expect(output.text == "4")
    }

    @Test func aModelWithoutSpanTokensIsNeverTagged() {
        var tagger = ThinkingSpanTagger(open: nil, close: nil)
        #expect(tagger.tag(for: 8) == nil)
        #expect(tagger.tag(for: 10) == nil)
    }
}
