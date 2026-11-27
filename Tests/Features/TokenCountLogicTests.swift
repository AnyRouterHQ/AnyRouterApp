import Testing
@testable import AnyRouter

/// Compaction and, later, the prompt assembler budget on this count. Undercounting Vietnamese or Chinese overflows a
/// 4,096-token device window, so those must count about one token per character.
struct TokenCountLogicTests {
    @Test func englishCountsAboutThreeCharactersAToken() {
        #expect(TokenCountLogic.estimate("") == 0)
        #expect(TokenCountLogic.estimate("abc") == 1)
        #expect(TokenCountLogic.estimate("abcd") == 2)
        #expect(TokenCountLogic.estimate("The quick brown fox") == 7)
    }

    @Test func vietnameseWordsWithMarksCountOneTokenACharacter() {
        // Tên, tôi, là: 8 characters at one each; Lan and the three spaces: 6 at a third.
        #expect(TokenCountLogic.estimate("Tên tôi là Lan") == 10)
        #expect(TokenCountLogic.estimate("Chào bạn") > TokenCountLogic.estimate("Chao ban"))
        // A tone mark written as a combining character counts like the precomposed letter.
        #expect(TokenCountLogic.estimate("a\u{0323}n") == TokenCountLogic.estimate("ạn"))
    }

    @Test func chineseCountsOneTokenACharacter() {
        #expect(TokenCountLogic.estimate("我叫兰") == 3)
        #expect(TokenCountLogic.estimate("こんにちは") == 5)
    }

    @Test func symbolsAndEmojiAreNotLetters() {
        #expect(TokenCountLogic.estimate("Hi 👋 — ok") == 3)
    }
}
