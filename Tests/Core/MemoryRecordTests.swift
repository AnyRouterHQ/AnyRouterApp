import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct MemoryRecordTests {
    @Test func aNewRecordStartsUnusedWithMatchingDates() {
        let now = Date(timeIntervalSince1970: 1_000)
        let record = MemoryRecord(kind: .fact, text: "My dog is called Mochi.", origin: .askedInChat, scope: .deviceOnly, now: now)
        #expect(record.kind == .fact && record.origin == .askedInChat && record.scope == .deviceOnly)
        #expect(record.createdAt == now && record.updatedAt == now)
        #expect(record.useCount == 0 && record.lastUsedAt == nil)
        #expect(record.embedding == nil && record.embeddingModel == nil)
    }

    @Test func settersWriteTheRawValuesTheStoreKeeps() {
        let record = MemoryRecord(kind: .note, text: "x", origin: .typedInSettings, scope: .everywhere)
        record.kind = .chatSummary
        record.origin = .modelTool
        record.scope = .deviceOnly
        #expect(record.kindRaw == "chatSummary" && record.originRaw == "modelTool" && record.scopeRaw == "deviceOnly")
    }

    @Test func unknownRawValuesFallBackToTheSafestChoice() {
        let record = MemoryRecord(kind: .fact, text: "x", origin: .extracted, scope: .everywhere)
        record.kindRaw = "future"
        record.originRaw = "future"
        record.scopeRaw = "future"
        #expect(record.kind == .note)
        #expect(record.origin == .typedInSettings)
        #expect(record.scope == .deviceOnly, "an item of unknown scope never reaches a cloud model")
    }

    @Test func lastTouchedIsTheLastUseElseTheSaveTime() {
        let record = MemoryRecord(kind: .note, text: "x", origin: .typedInSettings, scope: .everywhere, now: Date(timeIntervalSince1970: 10))
        #expect(record.lastTouched == Date(timeIntervalSince1970: 10))
        record.lastUsedAt = Date(timeIntervalSince1970: 50)
        #expect(record.lastTouched == Date(timeIntervalSince1970: 50))
    }

    @Test func aStoreWrittenWithoutMemoriesOpensWithTheNewSchema() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "chats.store")
        do {
            let old = try ModelContainer(
                for: ThreadRecord.self, MessageRecord.self, DecisionRunRecord.self,
                configurations: ModelConfiguration(url: url))
            let context = ModelContext(old)
            context.insert(ThreadRecord(title: "written before memories"))
            try context.save()
        }
        let context = ModelContext(try ModelContainer.anyRouter(storeURL: url))
        let threads = try context.fetch(FetchDescriptor<ThreadRecord>())
        #expect(threads.map(\.title) == ["written before memories"])
        context.insert(MemoryRecord(kind: .profile, text: "I live in Hue.", origin: .typedInSettings, scope: .everywhere))
        try context.save()
        let reopened = ModelContext(try ModelContainer.anyRouter(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<MemoryRecord>()).map(\.text) == ["I live in Hue."])
    }
}
