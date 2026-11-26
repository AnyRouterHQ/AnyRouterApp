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

    @Test func aReplyInProgressAlwaysOffersStop() {
        for input in [false, true] {
            for attachments in [false, true] {
                #expect(ComposerAction.current(isStreaming: true, hasInput: input, hasAttachments: attachments) == .stop)
            }
        }
    }

    @Test func eachActionHasItsOwnLabelAndSymbol() {
        let all: [ComposerAction] = [.voice, .send, .stop]
        #expect(Set(all.map(\.title)).count == 3)
        #expect(Set(all.map(\.symbol)).count == 3)
    }
}
