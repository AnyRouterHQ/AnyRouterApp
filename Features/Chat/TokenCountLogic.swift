import Foundation

/// How many tokens a text takes when the engine's own tokenizer is not at hand: cloud models, and the fallback for every
/// engine. Latin text runs about three characters a token; Vietnamese and CJK about one (Apple's context-window article).
/// A word with any letter outside ASCII (an accent, a tone mark, a CJK character) counts one token per character, every
/// other character one third. It overcounts English a little, which is the safe side for a small window.
enum TokenCountLogic {
    static func estimate(_ text: String) -> Int {
        var sparse = 0
        var dense = 0
        var word = 0
        var wordIsDense = false
        func endWord() {
            if wordIsDense { dense += word } else { sparse += word }
            word = 0
            wordIsDense = false
        }
        for character in text {
            if character.isWhitespace {
                endWord()
                sparse += 1
            } else {
                word += 1
                if !wordIsDense, isDense(character) { wordIsDense = true }
            }
        }
        endWord()
        return (sparse + 2) / 3 + dense
    }

    /// A letter outside ASCII, or a combining mark (a decomposed Vietnamese tone mark).
    private static func isDense(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            scalar.value > 0x7F && (scalar.properties.isAlphabetic || scalar.properties.generalCategory == .nonspacingMark)
        }
    }
}
