import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// A store in its own temporary folder. Call `cleanup()` when the test ends.
struct TempAttachments {
    let store: AttachmentStore
    private let folder: URL

    init() {
        folder = FileManager.default.temporaryDirectory.appending(path: "att-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = AttachmentStore(root: folder)
    }

    func cleanup() { try? FileManager.default.removeItem(at: folder) }

    func exists(_ attachment: ChatAttachment) -> Bool {
        FileManager.default.fileExists(atPath: attachment.url(in: store.root).path)
    }

    func attachment(_ text: String = "hi", name: String = "a.txt") throws -> ChatAttachment {
        let id = UUID()
        let path = try store.write(Data(text.utf8), id: id, fileExtension: "txt")
        return ChatAttachment(id: id, kind: .text, filename: name, utType: "public.plain-text",
                          byteCount: Int64(text.utf8.count), relativePath: path, extractedText: text)
    }
}

struct AttachmentStoreTests {
    @Test func newFilesWaitInThePendingFolderAndCanBeReadBack() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let attachment = try temp.attachment("hello")
        #expect(attachment.relativePath.hasPrefix("_pending/") && attachment.relativePath.hasSuffix(".txt"))
        #expect(temp.store.data(for: attachment) == Data("hello".utf8))
        #expect(temp.store.extractedText(for: attachment) == "hello")
    }

    @Test func aFileWithoutAnExtensionHasNoDot() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let id = UUID()
        #expect(try temp.store.write(Data(), id: id, fileExtension: "") == "_pending/\(id.uuidString)")
    }

    @Test func sendingMovesTheFileIntoTheThreadFolder() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let thread = UUID()
        let pending = try temp.attachment()
        let moved = try temp.store.adopt(pending, intoThread: thread)
        #expect(moved.relativePath.hasPrefix(thread.uuidString + "/"))
        #expect(temp.exists(moved) && !temp.exists(pending))
        #expect(moved.id == pending.id && moved.extractedText == "hi")
    }

    @Test func adoptingTwiceFailsBecauseTheSourceIsGone() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let pending = try temp.attachment()
        _ = try temp.store.adopt(pending, intoThread: UUID())
        #expect(throws: (any Error).self) { try temp.store.adopt(pending, intoThread: UUID()) }
    }

    @Test func removingDeletesTheFile() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let attachment = try temp.attachment()
        temp.store.remove(attachment)
        #expect(!temp.exists(attachment) && temp.store.data(for: attachment) == nil)
    }

    @Test func deletingAThreadDeletesOnlyItsFiles() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let mine = UUID(), other = UUID()
        let a = try temp.store.adopt(try temp.attachment(), intoThread: mine)
        let b = try temp.store.adopt(try temp.attachment(), intoThread: other)
        temp.store.deleteThread(mine)
        #expect(!temp.exists(a) && temp.exists(b))
    }

    @Test func deletingEverythingEmptiesTheRoot() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let a = try temp.store.adopt(try temp.attachment(), intoThread: UUID())
        temp.store.deleteAll()
        #expect(!temp.exists(a))
    }

    @Test func unsentFilesArePurgedButSentOnesStay() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let unsent = try temp.attachment()
        let sent = try temp.store.adopt(try temp.attachment(), intoThread: UUID())
        temp.store.purgePending()
        #expect(!temp.exists(unsent) && temp.exists(sent))
    }

    @Test func theAppStoreLivesInApplicationSupport() {
        #expect(AttachmentStore.defaultRoot.path.hasSuffix("Application Support/attachments"))
        #expect(AttachmentStore.shared.root == AttachmentStore.defaultRoot)
    }

    @MainActor
    @Test func deletingAThreadRemovesItsAttachmentFiles() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let thread = ThreadRecord(title: "t")
        context.insert(thread)
        let moved = try temp.store.adopt(try temp.attachment(), intoThread: thread.id)
        ThreadActions.delete(thread, in: context, files: temp.store)
        #expect(!temp.exists(moved))
    }

    @MainActor
    @Test func deletingAllThreadsRemovesEveryAttachmentFile() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let moved = try temp.store.adopt(try temp.attachment(), intoThread: UUID())
        ThreadActions.deleteAll(in: context, files: temp.store)
        #expect(!temp.exists(moved))
    }
}
