import Testing
@testable import AnyRouter

/// The top bar shows the chat's title once a reply exists, with the model name under it.
struct ChatHeaderLogicTests {
    @Test func theTitleShowsOnlyOnceTheChatHasAReply() {
        #expect(ChatHeaderLogic.title("Weekend in Porto", hasReply: true) == "Weekend in Porto")
        #expect(ChatHeaderLogic.title("Weekend in Porto", hasReply: false) == nil, "a question alone still shows the model")
        #expect(ChatHeaderLogic.title(nil, hasReply: true) == nil, "a new chat has no thread yet")
        #expect(ChatHeaderLogic.title("  ", hasReply: true) == nil)
        #expect(ChatHeaderLogic.title(" Trip ", hasReply: true) == "Trip")
    }
}
