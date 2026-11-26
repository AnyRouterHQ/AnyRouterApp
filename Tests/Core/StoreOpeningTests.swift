import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct StoreOpeningTests {
    private struct Refused: Error {}

    private func folder() -> URL { makeTempDirectory() }

    @Test func aStoreThatOpensIsUsedAsIsWithoutANote() throws {
        let url = folder().appending(path: "default.store")
        let outcome = try StoreOpening.open(at: url, make: { _ in try ModelContainer.anyRouter(inMemory: true) })
        #expect(outcome.note == nil)
    }

    @Test func aRealStoreIsCreatedOnDiskEvenWhenItsFolderDoesNotExistYet() throws {
        let url = folder().appending(path: "Later/default.store")
        let outcome = try StoreOpening.open(at: url)
        #expect(outcome.note == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aStoreThatCannotOpenIsKeptAsideAndReplaced() throws {
        let url = folder().appending(path: "default.store")
        try Data("old chats".utf8).write(to: url)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        var calls = 0
        let outcome = try StoreOpening.open(at: url, make: { target in
            calls += 1
            if calls == 1 { throw Refused() }
            #expect(target == url)
            return try ModelContainer.anyRouter(inMemory: true)
        }, now: Date(timeIntervalSince1970: 1_000))
        let kept = url.deletingLastPathComponent().appending(path: "default.store.unreadable-1000")
        #expect(try String(contentsOf: kept, encoding: .utf8) == "old chats")
        #expect(FileManager.default.fileExists(atPath: kept.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(outcome.note?.contains("default.store.unreadable-1000") == true)
        #expect(outcome.note?.contains("new chat history") == true)
    }

    @Test func whenNothingOnDiskWorksTheSessionRunsInMemoryAndSaysSo() throws {
        let url = folder().appending(path: "default.store")
        let outcome = try StoreOpening.open(at: url, make: { target in
            if target != nil { throw Refused() }
            return try ModelContainer.anyRouter(inMemory: true)
        })
        #expect(outcome.note?.contains("will not be kept") == true)
        #expect(outcome.note?.contains("kept as") == false, "there was no old file to keep")
    }

    @Test func movingAsideNeedsAFileToMove() {
        #expect(StoreOpening.moveAside(folder().appending(path: "none.store"), now: Date()) == nil)
    }

    @Test func theNoteIsShownOnce() {
        StoreOpening.post(note: "hello")
        #expect(StoreOpening.takeNote() == "hello")
        #expect(StoreOpening.takeNote() == nil)
    }

    @Test func theDefaultStoreKeepsItsOldLocationSoExistingChatsStayVisible() {
        #expect(StoreOpening.defaultStoreURL.lastPathComponent == "default.store")
        #expect(StoreOpening.defaultStoreURL.deletingLastPathComponent().path == URL.applicationSupportDirectory.path)
    }
}
