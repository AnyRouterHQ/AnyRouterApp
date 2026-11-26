import Testing
@testable import AnyRouter

struct TranscriptAssemblerTests {
    @Test func aRevisedPhraseReplacesItselfAndAFinalOneStays() {
        var assembler = TranscriptAssembler()
        assembler.apply("hello", isFinal: false)
        #expect(assembler.text == "hello")
        assembler.apply("hello world", isFinal: false)
        #expect(assembler.text == "hello world")
        assembler.apply("hello world.", isFinal: true)
        assembler.apply("how are", isFinal: false)
        #expect(assembler.text == "hello world. how are")
        assembler.apply("how are you?", isFinal: true)
        #expect(assembler.text == "hello world. how are you?")
        #expect(assembler.confirmed == "hello world. how are you?")
    }

    @Test func emptyPhrasesAddNoSpaces() {
        var assembler = TranscriptAssembler()
        assembler.apply("  ", isFinal: true)
        #expect(assembler.text == "")
        assembler.apply("hi", isFinal: true)
        assembler.apply("", isFinal: false)
        #expect(assembler.text == "hi")
    }
}
