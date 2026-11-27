import Foundation
import SwiftData
import Testing

@testable import AnyRouter

/// The files the @ list offers: those waiting under the field, then those of the chat.
@MainActor
struct MentionFilesChatTests {
    private struct Rig {
        let vm: ChatViewModel
        let temp: TempAttachments
    }

    private func rig() async throws -> Rig {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(models: [testModel()], chunks: ["ok"]))
        let store = ModelStore(registry: registry, defaults: testDefaults())
        await store.refresh()
        let temp = TempAttachments()
        let vm = ChatViewModel(
            thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()),
            models: store, attachments: temp.store)
        return Rig(vm: vm, temp: temp)
    }

    /// Waits for the readers themselves: no polling, no deadline to outrun on a slow runner.
    private func settle(_ vm: ChatViewModel) async {
        await vm.finishIngesting()
        #expect(vm.ingesting == 0)
    }

    private func textFile(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "m-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data("text of \(name)".utf8).write(to: url)
        return url
    }

    @Test func aNewChatOffersNoFiles() async throws {
        let r = try await rig()
        defer { r.temp.cleanup() }
        #expect(r.vm.mentionableFiles.isEmpty)
    }

    @Test func pendingFilesComeFirstThenTheFilesAlreadySentInTheChat() async throws {
        let r = try await rig()
        defer { r.temp.cleanup() }
        r.vm.attachFiles([try textFile("first.txt")])
        await settle(r.vm)
        #expect(r.vm.mentionableFiles.map(\.filename) == ["first.txt"])

        r.vm.input = "read it"
        await r.vm.send()?.value
        #expect(r.vm.pending.isEmpty)
        #expect(r.vm.mentionableFiles.map(\.filename) == ["first.txt"], "now it belongs to the chat")

        r.vm.attachFiles([try textFile("second.txt")])
        await settle(r.vm)
        #expect(r.vm.mentionableFiles.map(\.filename) == ["second.txt", "first.txt"])
    }

    @Test func aChatWithOnlyFilesIsTitledByTheFirstFileName() {
        let file = ChatAttachment(id: UUID(), kind: .text, filename: "plan.txt", utType: "public.plain-text", byteCount: 1, relativePath: "t/plan.txt")
        #expect(ChatViewModel.attachmentTitle([file]) == "plan.txt")
        #expect(ChatViewModel.attachmentTitle([]) == "Attachment")
    }
}
