import Foundation
import SwiftData
import Testing
@testable import AnyRouter

struct InstructionsLogicTests {
    @Test func aChatsOwnInstructionsBeatTheGlobalOnesWhichBeatNothing() {
        #expect(InstructionsLogic.effective(chat: "Chat rules", global: "Global rules") == "Chat rules")
        #expect(InstructionsLogic.effective(chat: nil, global: "Global rules") == "Global rules")
        #expect(InstructionsLogic.effective(chat: nil, global: "") == nil)
    }

    @Test func blankTextCountsAsNoneSoTheNextLevelApplies() {
        #expect(InstructionsLogic.effective(chat: "  \n ", global: "  Global  ") == "Global")
        #expect(InstructionsLogic.effective(chat: "", global: "   ") == nil)
    }

    @Test func templatesFillAnEmptyEditorAndAppendAfterAnythingWritten() {
        let concise = InstructionsLogic.templates[0]
        #expect(InstructionsLogic.inserting(concise, into: "") == concise.text)
        #expect(InstructionsLogic.inserting(concise, into: "  \n") == concise.text)
        #expect(InstructionsLogic.inserting(concise, into: "Call me Sam. ") == "Call me Sam.\n\n" + concise.text)
    }

    @Test func aTemplateIsNotAddedTwice() {
        let teacher = InstructionsLogic.templates[1]
        let once = InstructionsLogic.inserting(teacher, into: "")
        #expect(InstructionsLogic.inserting(teacher, into: once) == once)
    }

    @Test func thereAreFourStarterTemplatesWithTheNamesTheUserAskedFor() {
        #expect(InstructionsLogic.templates.map(\.title) == ["Concise", "Teacher", "Vietnamese replies", "Code reviewer"])
        #expect(Set(InstructionsLogic.templates.map(\.id)).count == 4)
        #expect(InstructionsLogic.templates.allSatisfy { !$0.text.isEmpty })
    }

    @Test func theCountSaysCharactersAndWarnsWhenLong() {
        #expect(InstructionsLogic.countText("") == "0 characters")
        #expect(InstructionsLogic.countText(" a ") == "1 character")
        #expect(InstructionsLogic.countText("abcd") == "4 characters")
        let long = String(repeating: "a", count: InstructionsLogic.longLimit + 1)
        #expect(InstructionsLogic.countText(long) == "\(InstructionsLogic.longLimit + 1) characters. Long for small on-device models.")
    }

    @Test func theNoteSaysWhichModelsUseTheText() {
        #expect(InstructionsLogic.usageNote(hasInstructions: false, defaultModelName: "GPT-5") == "Nothing is added. Every model answers with its own defaults.")
        #expect(InstructionsLogic.usageNote(hasInstructions: true, defaultModelName: nil)
            == "Used by every model: Apple Intelligence, on-device models and AnyRouter models.")
        #expect(InstructionsLogic.usageNote(hasInstructions: true, defaultModelName: "GPT-5")
            == "Used by every model: GPT-5 (your default), Apple Intelligence, on-device models and AnyRouter models.")
    }

    @Test func theHeaderTagShowsOnlyForAChatWithItsOwnInstructions() {
        #expect(InstructionsLogic.headerTag(chat: "Be brief") == "Custom instructions")
        #expect(InstructionsLogic.headerTag(chat: nil) == nil)
        #expect(InstructionsLogic.headerTag(chat: "  ") == nil)
    }

    @Test func theSettingsRowShowsOffOrTheStartOfTheText() {
        #expect(InstructionsLogic.summary(global: "  ") == "Off")
        #expect(InstructionsLogic.summary(global: "Short") == "Short")
        #expect(InstructionsLogic.summary(global: String(repeating: "x", count: 60)) == String(repeating: "x", count: 40) + "…")
    }
}

@MainActor
struct ChatInstructionsTests {
    private struct Rig {
        let vm: ChatViewModel
        let engine: ScriptedEngine
        let context: ModelContext
        let registry: EngineRegistry
        let models: ModelStore
        let settings: AppSettings
    }

    private func rig(global: String = "") async throws -> Rig {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let engine = ScriptedEngine(chunks: ["ok"])
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let settings = AppSettings(defaults: testDefaults())
        settings.systemPrompt = global
        let vm = ChatViewModel(thread: nil, context: context, registry: registry, settings: settings, models: models)
        return Rig(vm: vm, engine: engine, context: context, registry: registry, models: models, settings: settings)
    }

    @Test func theEngineGetsTheChatOverrideThenTheGlobalThenNothing() async throws {
        let r = try await rig(global: "Global")
        r.vm.input = "one"
        await r.vm.send()?.value
        r.vm.setChatInstructions("  Chat rules  ")
        r.vm.input = "two"
        await r.vm.send()?.value
        r.vm.setChatInstructions("   ")
        r.vm.input = "three"
        await r.vm.send()?.value
        r.settings.systemPrompt = ""
        r.vm.input = "four"
        await r.vm.send()?.value
        #expect(r.engine.systemPromptsSeen.seen == ["Global", "Chat rules", "Global", nil])
    }

    @Test func instructionsSetBeforeTheFirstSendAreSavedWithTheNewThread() async throws {
        let r = try await rig()
        r.vm.setChatInstructions("Answer in French")
        #expect(r.vm.chatInstructions == "Answer in French")
        r.vm.input = "hi"
        await r.vm.send()?.value
        #expect(r.vm.thread?.instructions == "Answer in French")
        #expect(r.engine.systemPromptsSeen.seen == ["Answer in French"])
    }

    @Test func theOverrideComesBackWhenTheThreadIsOpenedAgain() async throws {
        let r = try await rig()
        r.vm.input = "hi"
        await r.vm.send()?.value
        r.vm.setChatInstructions("Be brief")
        let reopened = ChatViewModel(thread: r.vm.thread, context: r.context, registry: r.registry, settings: r.settings, models: r.models)
        #expect(reopened.chatInstructions == "Be brief")
        reopened.setChatInstructions(nil)
        #expect(reopened.thread?.instructions == nil)
        #expect(reopened.chatInstructions == nil)
    }

    @Test func aChatWithoutAnOverrideLeavesTheThreadClean() async throws {
        let r = try await rig()
        r.vm.input = "hi"
        await r.vm.send()?.value
        #expect(r.vm.thread?.instructions == nil)
    }
}
