import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct RecordsTests {
    @Test func messagesComeBackInCreationOrder() throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let thread = ThreadRecord(title: "t")
        context.insert(thread)
        let t0 = Date(timeIntervalSince1970: 100)
        for (i, text) in ["b", "a", "c"].enumerated() {
            let m = MessageRecord(role: .user, content: text, createdAt: t0.addingTimeInterval(Double(2 - i)))
            m.thread = thread
            context.insert(m)
        }
        try context.save()
        #expect(thread.orderedMessages.map(\.content) == ["c", "a", "b"])
    }

    @Test func deletingThreadDeletesItsMessages() throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let thread = ThreadRecord()
        context.insert(thread)
        let m = MessageRecord(role: .assistant, content: "x")
        m.thread = thread
        context.insert(m)
        try context.save()
        context.delete(thread)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<MessageRecord>()).isEmpty)
    }

    @Test func chatMessageSurvivesRecordRoundTrip() {
        let original = ChatMessage(role: .system, content: "be brief")
        #expect(MessageRecord(original).chatMessage == original)
    }

    @Test func unknownStoredRoleFallsBackToAssistant() {
        let r = MessageRecord(role: .user, content: "x")
        r.roleRaw = "tool"
        #expect(r.role == .assistant)
    }
}
