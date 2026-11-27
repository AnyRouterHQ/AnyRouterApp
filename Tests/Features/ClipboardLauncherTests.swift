import Foundation
import SwiftData
import Testing
@testable import AnyRouter

final class FakePasteboard: PasteboardProbe, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 1
    private var strings = true
    var changeCount: Int { lock.withLock { count } }
    var hasStrings: Bool { lock.withLock { strings } }
    func copy() { lock.withLock { count += 1; strings = true } }
    func clear() { lock.withLock { count += 1; strings = false } }
}

struct ClipboardLaunchLogicTests {
    @Test func textCopiedSinceTheLastOfferIsOfferedWhenTheMessageIsEmpty() {
        #expect(ClipboardLaunchLogic.shouldOffer(changeCount: 5, lastSeen: 4, hasStrings: true, composerEmpty: true))
        #expect(ClipboardLaunchLogic.shouldOffer(changeCount: 5, lastSeen: nil, hasStrings: true, composerEmpty: true), "first launch")
    }

    @Test func theSameClipboardIsNotOfferedTwice() {
        #expect(!ClipboardLaunchLogic.shouldOffer(changeCount: 5, lastSeen: 5, hasStrings: true, composerEmpty: true))
    }

    @Test func nothingIsOfferedWithoutTextOrWithAMessageInProgress() {
        #expect(!ClipboardLaunchLogic.shouldOffer(changeCount: 5, lastSeen: 4, hasStrings: false, composerEmpty: true))
        #expect(!ClipboardLaunchLogic.shouldOffer(changeCount: 5, lastSeen: 4, hasStrings: true, composerEmpty: false))
    }
}

@MainActor
struct ClipboardLauncherTests {
    private func launcher(_ board: FakePasteboard, _ defaults: UserDefaults = testDefaults()) -> ClipboardLauncher {
        ClipboardLauncher(probe: board, defaults: defaults)
    }

    @Test func aFreshCopyShowsTheRowOnceAndRemembersIt() {
        let board = FakePasteboard()
        let defaults = testDefaults()
        let first = launcher(board, defaults)
        first.check(composerEmpty: true)
        #expect(first.isOffered)
        first.dismiss()
        first.check(composerEmpty: true)
        #expect(!first.isOffered, "the same clipboard is offered once")
        // Also after a relaunch.
        let second = launcher(board, defaults)
        second.check(composerEmpty: true)
        #expect(!second.isOffered)
        board.copy()
        second.check(composerEmpty: true)
        #expect(second.isOffered, "a new copy is offered again")
    }

    @Test func aMessageInProgressOrAnEmptyClipboardOffersNothing() {
        let board = FakePasteboard()
        let l = launcher(board)
        l.check(composerEmpty: false)
        #expect(!l.isOffered)
        board.clear()
        l.check(composerEmpty: true)
        #expect(!l.isOffered)
    }

    @Test func aMessageInProgressDoesNotUseUpTheOffer() {
        let board = FakePasteboard()
        let l = launcher(board)
        l.check(composerEmpty: false)
        l.check(composerEmpty: true)
        #expect(l.isOffered)
    }

    @Test func textTheAppCopiedItselfIsNotOfferedBack() {
        let board = FakePasteboard()
        let l = launcher(board)
        board.copy()
        l.noteOwnCopy()
        l.check(composerEmpty: true)
        #expect(!l.isOffered)
        board.copy()
        l.check(composerEmpty: true)
        #expect(l.isOffered)
    }

    @Test func theDemoPasteboardOffersTheRowOnEveryLaunch() {
        #expect(DemoPasteboard().hasStrings)
        let l = ClipboardLauncher(probe: DemoPasteboard(), defaults: testDefaults())
        l.check(composerEmpty: true)
        #expect(l.isOffered)
    }

    @Test func offDeviceProbesAreInert() {
        #expect(!EmptyPasteboard().hasStrings)
        #expect(EmptyPasteboard().changeCount == 0)
        let l = ClipboardLauncher(probe: EmptyPasteboard(), defaults: testDefaults())
        l.check(composerEmpty: true)
        #expect(!l.isOffered)
    }
}

@MainActor
struct ClipboardPresetTests {
    private let fix = PromptPreset(id: "fix", title: "Fix", prompt: "Fix this:\n", category: .write, symbol: "sparkles", offerOnPaste: true)

    private func chat() async throws -> ChatViewModel {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["done"]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return ChatViewModel(thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models)
    }

    @Test func aPresetTappedInTheClipboardRowSendsThePromptWithTheText() async throws {
        let vm = try await chat()
        await vm.useClipboard(fix, text: "  Me and him goes to school.  \n")?.value
        #expect(vm.messages.first?.content == "Fix this:\nMe and him goes to school.")
        #expect(vm.messages.last?.content == "done")
    }

    @Test func aPresetWithPickersOpensItsChoicesWithTheTextAsTheMessage() async throws {
        let vm = try await chat()
        var reply = fix
        reply.options = [PresetOption(id: "tone", title: "Tone", choices: [.init(id: "polite", title: "Polite", wording: "polite")])]
        #expect(vm.useClipboard(reply, text: "Hello there") == nil)
        #expect(vm.presetNeedingChoices?.id == "fix")
        #expect(vm.input == "Hello there")
        #expect(vm.messages.isEmpty)
    }

    @Test func anEmptyClipboardDoesNothing() async throws {
        let vm = try await chat()
        #expect(vm.useClipboard(fix, text: "  \n") == nil)
        #expect(vm.input.isEmpty && vm.presetNeedingChoices == nil && vm.messages.isEmpty)
    }
}
