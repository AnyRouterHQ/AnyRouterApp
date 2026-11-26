import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct SettingPreviewTests {
    @Test func theSampleReplyCarriesEverythingTheResponseDetailsLineShows() {
        let reply = DemoData.sampleReply()
        #expect(reply.role == .assistant)
        #expect(!reply.content.isEmpty)
        #expect(reply.metadata?.servedModelName == "GPT-5")
        #expect(reply.metadata?.costUSD != nil)
        #expect(reply.metadata?.ttftMs != nil)
        #expect(reply.modelID == "anyrouter/openai/gpt-5", "the footer can draw the model logo")
    }

    @Test func theSampleIsNeverStored() {
        #expect(DemoData.sampleReply().thread == nil)
        #expect(DemoData.sampleReply().id != DemoData.sampleReply().id)
    }
}
