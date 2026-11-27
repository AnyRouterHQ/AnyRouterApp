import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// A failed reply is saved with the reply, so reopening the chat or relaunching the app shows the same failure.
@MainActor
struct ReplyFailureStoreTests {
    @Test func aFailedReplyReadsBackFromDiskWithItsKindDetailTextAndSteps() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "chats.store")
        let call = ToolCall(id: "c1", name: "web_search", argumentsJSON: #"{"query":"q"}"#)
        let step = ToolStep(call: call, result: ToolResult(callID: "c1", name: "web_search", text: "socket closed", isError: true), sourceID: nil)
        let saved = ReplyFailure(kind: .rateLimited, detail: "HTTP 429: slow down")
        let threadID: UUID
        do {
            let context = ModelContext(try ModelContainer.anyRouter(storeURL: url))
            let thread = ThreadRecord(title: "t")
            context.insert(thread)
            let reply = MessageRecord(role: .assistant, content: "half an answer")
            context.insert(reply)
            reply.thread = thread
            reply.toolSteps = [step]
            reply.failure = saved
            try context.save()
            threadID = thread.id
        }
        let reopened = ModelContext(try ModelContainer.anyRouter(storeURL: url))
        let reply = try #require(try reopened.fetch(FetchDescriptor<MessageRecord>()).first)
        #expect(reply.failure == saved)
        #expect(reply.content == "half an answer")
        #expect(reply.toolSteps == [step])
        #expect(reply.thread?.id == threadID)
    }

    @Test func aReplySavedWithoutAFailureReadsAsNone() {
        let reply = MessageRecord(role: .assistant, content: "ok")
        #expect(reply.failureData == nil && reply.failure == nil)
        reply.failure = ReplyFailure(kind: .timeout, detail: "x")
        #expect(reply.failureData != nil)
        reply.failure = nil
        #expect(reply.failureData == nil)
        reply.failureData = Data("not json".utf8)
        #expect(reply.failure == nil, "a damaged value reads as no failure")
    }
}
