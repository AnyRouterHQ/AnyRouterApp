import Testing
@testable import AnyRouter

struct ComposerLogicTests {
    @Test func emptyFieldOffersVoice() {
        #expect(ComposerAction.current(isStreaming: false, hasInput: false, hasAttachments: false) == .voice)
    }

    @Test func textOrAnAttachmentOffersSend() {
        #expect(ComposerAction.current(isStreaming: false, hasInput: true, hasAttachments: false) == .send)
        #expect(ComposerAction.current(isStreaming: false, hasInput: false, hasAttachments: true) == .send)
    }

    @Test func aReplyInProgressOffersStopUntilSomethingIsTyped() {
        #expect(ComposerAction.current(isStreaming: true, hasInput: false, hasAttachments: false) == .stop)
    }

    @Test func typingDuringAReplyOffersTheQueue() {
        #expect(ComposerAction.current(isStreaming: true, hasInput: true, hasAttachments: false) == .queue)
        #expect(ComposerAction.current(isStreaming: true, hasInput: false, hasAttachments: true) == .queue)
    }

    @Test func eachActionHasItsOwnLabelAndSymbol() {
        let all: [ComposerAction] = [.voice, .send, .stop, .queue]
        #expect(Set(all.map(\.title)).count == 4)
        #expect(Set(all.map(\.symbol)).count == 4)
    }

    @Test func dictationTurnsTheButtonIntoStopDictationUnlessAReplyIsStreaming() {
        #expect(ComposerAction.current(isStreaming: false, hasInput: true, hasAttachments: false, isDictating: true) == .stopDictation)
        #expect(ComposerAction.current(isStreaming: false, hasInput: false, hasAttachments: false, isDictating: true) == .stopDictation)
        #expect(ComposerAction.current(isStreaming: true, hasInput: false, hasAttachments: false, isDictating: true) == .stop)
        #expect(ComposerAction.stopDictation.title == "Stop dictation")
        #expect(ComposerAction.stopDictation.symbol != ComposerAction.voice.symbol)
    }
}
