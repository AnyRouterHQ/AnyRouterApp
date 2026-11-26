import Foundation
import Testing
@testable import AnyRouter

struct SyntaxHighlighterTests {
    private func kinds(_ code: String, _ language: String?) -> [(SyntaxHighlighter.Kind, String)] {
        SyntaxHighlighter.tokens(code, language: language).map { ($0.kind, $0.text) }
    }

    private func joined(_ code: String, _ language: String?) -> String {
        SyntaxHighlighter.tokens(code, language: language).map(\.text).joined()
    }

    @Test func swiftKeywordsStringsAndCommentsAreFound() {
        let tokens = SyntaxHighlighter.tokens("let name = \"Ada\" // who", language: "swift")
        #expect(tokens.contains(SyntaxHighlighter.Token(kind: .keyword, text: "let")))
        #expect(tokens.contains(SyntaxHighlighter.Token(kind: .string, text: "\"Ada\"")))
        #expect(tokens.contains(SyntaxHighlighter.Token(kind: .comment, text: "// who")))
        #expect(!tokens.contains(SyntaxHighlighter.Token(kind: .keyword, text: "name")))
    }

    @Test func aKeywordInsideAWordIsNotAKeyword() {
        let tokens = SyntaxHighlighter.tokens("letter format", language: "swift")
        #expect(tokens.allSatisfy { $0.kind == .plain })
    }

    @Test func aKeywordInsideAStringOrCommentStaysThere() {
        let tokens = SyntaxHighlighter.tokens("// let x\n\"let\"", language: "swift")
        #expect(tokens.filter { $0.kind == .keyword }.isEmpty)
    }

    @Test func pythonUsesHashCommentsAndTripleQuotes() {
        let code = "def f():\n    \"\"\"doc\n    more\"\"\"  # note\n    return None"
        let tokens = SyntaxHighlighter.tokens(code, language: "python")
        #expect(tokens.contains(SyntaxHighlighter.Token(kind: .keyword, text: "def")))
        #expect(tokens.contains(SyntaxHighlighter.Token(kind: .string, text: "\"\"\"doc\n    more\"\"\"")))
        #expect(tokens.contains(SyntaxHighlighter.Token(kind: .comment, text: "# note")))
        #expect(tokens.contains(SyntaxHighlighter.Token(kind: .keyword, text: "None")))
    }

    @Test func aBlockCommentSpansLinesAndIfUnterminatedRunsToTheEnd() {
        #expect(kinds("a /* x\ny */ b", "c").map(\.0).contains(.comment))
        let open = SyntaxHighlighter.tokens("a /* never closed\nstill comment", language: "c")
        #expect(open.last == SyntaxHighlighter.Token(kind: .comment, text: "/* never closed\nstill comment"))
    }

    /// A string that is still streaming in must not colour the lines after it.
    @Test func anUnterminatedStringEndsAtTheLineEnd() {
        let tokens = SyntaxHighlighter.tokens("let a = \"open\nlet b = 1", language: "swift")
        #expect(tokens.contains(SyntaxHighlighter.Token(kind: .string, text: "\"open")))
        #expect(tokens.filter { $0.kind == .keyword }.count == 2)
    }

    @Test func anEscapedQuoteDoesNotEndTheString() {
        let tokens = SyntaxHighlighter.tokens(#"print("a\"b")"#, language: "swift")
        #expect(tokens.contains(SyntaxHighlighter.Token(kind: .string, text: #""a\"b""#)))
    }

    @Test func templateStringsInScriptsMayRunOverLines() {
        let tokens = SyntaxHighlighter.tokens("const s = `a\nb`", language: "ts")
        #expect(tokens.contains(SyntaxHighlighter.Token(kind: .string, text: "`a\nb`")))
    }

    @Test func sqlKeywordsMatchInAnyCase() {
        let tokens = SyntaxHighlighter.tokens("SELECT id FROM t -- all", language: "sql")
        #expect(tokens.filter { $0.kind == .keyword }.map(\.text) == ["SELECT", "FROM"])
        #expect(tokens.last?.kind == .comment)
    }

    @Test func languageNamesAreCaseInsensitiveAndAliased() {
        #expect(!SyntaxHighlighter.tokens("let x", language: "Swift").allSatisfy { $0.kind == .plain })
        #expect(!SyntaxHighlighter.tokens("fn main() {}", language: "rs").allSatisfy { $0.kind == .plain })
        #expect(!SyntaxHighlighter.tokens("echo hi # c", language: "zsh").allSatisfy { $0.kind == .plain })
    }

    @Test func anUnknownOrMissingLanguageStaysPlain() {
        #expect(kinds("let x = 1", nil).map(\.0) == [.plain])
        #expect(kinds("let x = 1", "").map(\.0) == [.plain])
        #expect(kinds("let x = 1", "brainfuck").map(\.0) == [.plain])
        #expect(SyntaxHighlighter.tokens("", language: "swift").isEmpty)
    }

    @Test func hugeCodeIsNotHighlighted() {
        let code = String(repeating: "let a = 1\n", count: SyntaxHighlighter.limit / 5)
        #expect(SyntaxHighlighter.tokens(code, language: "swift").count == 1)
    }

    /// Highlighting never changes the text, whatever the input looks like.
    @Test func tokensAlwaysJoinBackToTheInput() {
        let samples = ["let a = \"x\\", "/* open", "'a\nb'", "# c\n#!/bin/sh", "\"\"\"x", "a//b", "`x", "    ", "é = 'ü'"]
        for language in ["swift", "python", "sh", "ts", "sql", "json", "yaml", "c"] {
            for sample in samples { #expect(joined(sample, language) == sample, "\(language): \(sample)") }
        }
    }

    @Test func codeBlocksCountTheirLinesForTheGutter() {
        #expect(CodeBlockView.lineCount("") == 1)
        #expect(CodeBlockView.lineCount("one") == 1)
        #expect(CodeBlockView.lineCount("a\nb\n\nd") == 4)
    }
}
