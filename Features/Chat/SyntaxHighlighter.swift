import Foundation

/// A small tokenizer for code blocks: keywords, strings and comments, nothing else. It is not a parser, so an
/// odd corner may be coloured wrong, but it never changes the text: the tokens always join back to the input.
/// A language it does not know, or code over `limit` characters, stays plain.
enum SyntaxHighlighter {
    enum Kind: Equatable { case plain, keyword, string, comment }

    struct Token: Equatable {
        var kind: Kind
        var text: String
    }

    static let limit = 20_000

    static func tokens(_ code: String, language: String?) -> [Token] {
        guard !code.isEmpty else { return [] }
        guard let rules = Rules.forLanguage(language), code.count <= limit else { return [Token(kind: .plain, text: code)] }
        return scan(Array(code), rules)
    }

    struct Rules {
        var keywords: Set<String>
        var lineComments: [[Character]] = []
        var blockComment: (open: [Character], close: [Character])?
        var quotes: Set<Character> = ["\"", "'"]
        /// Quote characters whose strings may run over several lines.
        var multilineQuotes: Set<Character> = []
        var tripleQuotes = false
        var caseInsensitive = false

        static func forLanguage(_ name: String?) -> Rules? {
            guard let name = name?.lowercased().trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            switch name {
            case "swift": return cLike(SyntaxHighlighter.swiftKeywords)
            case "js", "jsx", "javascript", "ts", "tsx", "typescript":
                var rules = cLike(SyntaxHighlighter.scriptKeywords)
                rules.quotes.insert("`")
                rules.multilineQuotes = ["`"]
                return rules
            case "go", "golang": return cLike(SyntaxHighlighter.goKeywords)
            case "rust", "rs": return cLike(SyntaxHighlighter.rustKeywords)
            case "java", "kotlin", "kt", "c", "cpp", "c++", "h", "hpp", "cs", "csharp", "objc", "dart":
                return cLike(SyntaxHighlighter.clikeKeywords)
            case "py", "python":
                var rules = Rules(keywords: SyntaxHighlighter.pythonKeywords, lineComments: [["#"]])
                rules.tripleQuotes = true
                return rules
            case "sh", "bash", "shell", "zsh": return Rules(keywords: SyntaxHighlighter.shellKeywords, lineComments: [["#"]])
            case "yaml", "yml": return Rules(keywords: ["true", "false", "null"], lineComments: [["#"]])
            case "json", "jsonc": return Rules(keywords: ["true", "false", "null"], quotes: ["\""])
            case "sql":
                var rules = Rules(keywords: SyntaxHighlighter.sqlKeywords, lineComments: [["-", "-"]])
                rules.blockComment = (["/", "*"], ["*", "/"])
                rules.caseInsensitive = true
                return rules
            default: return nil
            }
        }

        private static func cLike(_ keywords: Set<String>) -> Rules {
            Rules(keywords: keywords, lineComments: [["/", "/"]], blockComment: (["/", "*"], ["*", "/"]))
        }
    }

    private static func scan(_ chars: [Character], _ rules: Rules) -> [Token] {
        var tokens: [Token] = []
        var plain = ""
        func flush() {
            if !plain.isEmpty { tokens.append(Token(kind: .plain, text: plain)) }
            plain = ""
        }
        func emit(_ kind: Kind, _ range: Range<Int>) {
            flush()
            tokens.append(Token(kind: kind, text: String(chars[range])))
        }
        func matches(_ marker: [Character], at index: Int) -> Bool {
            index + marker.count <= chars.count && Array(chars[index..<(index + marker.count)]) == marker
        }
        func find(_ marker: [Character], from index: Int) -> Int? {
            var i = index
            while i + marker.count <= chars.count {
                if matches(marker, at: i) { return i }
                i += 1
            }
            return nil
        }
        func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if let block = rules.blockComment, matches(block.open, at: i) {
                let end = find(block.close, from: i + block.open.count).map { $0 + block.close.count } ?? chars.count
                emit(.comment, i..<end)
                i = end
            } else if rules.lineComments.contains(where: { matches($0, at: i) }) {
                var end = i
                while end < chars.count, chars[end] != "\n" { end += 1 }
                emit(.comment, i..<end)
                i = end
            } else if rules.quotes.contains(c) {
                let end = stringEnd(chars, from: i, rules: rules)
                emit(.string, i..<end)
                i = end
            } else if c.isLetter || c == "_" {
                var end = i
                while end < chars.count, isWord(chars[end]) { end += 1 }
                let word = String(chars[i..<end])
                if rules.keywords.contains(rules.caseInsensitive ? word.lowercased() : word) {
                    emit(.keyword, i..<end)
                } else {
                    plain += word
                }
                i = end
            } else {
                plain.append(c)
                i += 1
            }
        }
        flush()
        return tokens
    }

    /// The index just after the string that starts at `start`. An unterminated string ends at the line end
    /// (the end of the text for a multi-line quote), so a streaming block never colours the rest of the code.
    private static func stringEnd(_ chars: [Character], from start: Int, rules: Rules) -> Int {
        let quote = chars[start]
        if rules.tripleQuotes, start + 2 < chars.count, chars[start + 1] == quote, chars[start + 2] == quote {
            var i = start + 3
            while i + 2 < chars.count {
                if chars[i] == quote, chars[i + 1] == quote, chars[i + 2] == quote { return i + 3 }
                i += 1
            }
            return chars.count
        }
        var i = start + 1
        while i < chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == quote { return i + 1 }
            if chars[i] == "\n", !rules.multilineQuotes.contains(quote) { return i }
            i += 1
        }
        return chars.count
    }

    // MARK: Keywords

    private static let swiftKeywords: Set<String> = [
        "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue", "default",
        "defer", "deinit", "do", "else", "enum", "extension", "false", "fileprivate", "final", "for", "func", "guard", "if",
        "import", "in", "indirect", "init", "inout", "internal", "is", "let", "mutating", "nil", "nonisolated", "open",
        "operator", "override", "private", "protocol", "public", "repeat", "return", "self", "Self", "some", "static",
        "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while",
    ]
    private static let scriptKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "delete", "do", "else",
        "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements", "import", "in",
        "instanceof", "interface", "let", "new", "null", "of", "private", "public", "readonly", "return", "static",
        "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield",
    ]
    private static let pythonKeywords: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except",
        "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or",
        "pass", "raise", "return", "True", "try", "while", "with", "yield",
    ]
    private static let shellKeywords: Set<String> = [
        "case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function", "if", "in", "local", "return",
        "select", "then", "until", "while",
    ]
    private static let goKeywords: Set<String> = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "false", "for", "func",
        "go", "goto", "if", "import", "interface", "map", "nil", "package", "range", "return", "select", "struct", "switch",
        "true", "type", "var",
    ]
    private static let rustKeywords: Set<String> = [
        "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "false", "fn", "for", "if",
        "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static",
        "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while",
    ]
    private static let clikeKeywords: Set<String> = [
        "abstract", "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum", "extends",
        "false", "final", "finally", "for", "fun", "if", "implements", "import", "include", "interface", "namespace",
        "new", "null", "nullptr", "override", "package", "private", "protected", "public", "return", "static", "struct",
        "super", "switch", "this", "throw", "throws", "true", "try", "typedef", "using", "val", "var", "virtual", "void",
        "while",
    ]
    private static let sqlKeywords: Set<String> = [
        "select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete", "create",
        "table", "drop", "alter", "join", "left", "right", "inner", "outer", "on", "group", "by", "order", "limit",
        "having", "as", "distinct", "null", "is", "in", "like", "union", "case", "when", "then", "else", "end",
    ]
}
