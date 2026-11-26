import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct HomeTests {
    private func model(_ id: String, _ source: ModelSource, name: String? = nil, caps: Set<String> = ["chat"]) -> ModelDescriptor {
        ModelDescriptor(id: id, source: source, displayName: name ?? id, contextLength: nil,
                        capabilities: caps, sizeBytes: nil, isInstalled: true)
    }

    @Test func subtitleNamesTheSelectedModel() {
        #expect(HomeLogic.subtitle(for: nil) == HomeLogic.noModelSubtitle)
        #expect(HomeLogic.subtitle(for: model("anyrouter/anyrouter/auto", .anyrouter, name: "Auto"))
            == "Using AnyRouter · picks the best model")
        #expect(HomeLogic.subtitle(for: model("anyrouter/openai/gpt-x", .anyrouter, name: "GPT X"))
            == "Using AnyRouter · GPT X")
        #expect(HomeLogic.subtitle(for: model("apple/foundation", .apple)).contains("Apple Intelligence"))
        #expect(HomeLogic.subtitle(for: model("mlx/x", .mlx, name: "Qwen3 1.7B")) == "Using Qwen3 1.7B · on device")
    }

    @Test func thinkingOnlyForReasoningModels() {
        #expect(model("a", .gguf, caps: ["chat", "reasoning"]).supportsThinking)
        #expect(!model("b", .anyrouter, caps: ["chat", "tools"]).supportsThinking)
        #expect(!model("c", .apple).supportsThinking)
    }

    private func makeVM(engineModel: ModelDescriptor, container: ModelContainer, context: ModelContext? = nil, thread: ThreadRecord? = nil) async -> ChatViewModel {
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(source: engineModel.source, models: [engineModel], chunks: ["ok"]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return ChatViewModel(thread: thread, context: context ?? ModelContext(container), registry: registry,
                             settings: AppSettings(defaults: testDefaults()), models: models)
    }

    @Test func viewModelExposesThinkingSupportPerSelectedModel() async throws {
        let container = try ModelContainer.anyRouter(inMemory: true)
        let reasoning = await makeVM(engineModel: model("apple/r", .apple, caps: ["chat", "reasoning"]), container: container)
        let plain = await makeVM(engineModel: model("apple/p", .apple), container: container)
        #expect(reasoning.supportsThinking)
        #expect(!plain.supportsThinking)
    }

    @Test func thinkingFlagPersistsWithTheThread() async throws {
        let container = try ModelContainer.anyRouter(inMemory: true)
        let r = model("apple/r", .apple, caps: ["chat", "reasoning"])
        let context = ModelContext(container)
        let vm = await makeVM(engineModel: r, container: container, context: context)
        vm.setThinkingEnabled(true)
        vm.input = "hello"
        await vm.send()?.value
        let thread = try #require(vm.thread)
        #expect(thread.thinkingEnabled)

        // A fresh view model on the stored thread restores the flag, and toggling off is saved.
        let again = await makeVM(engineModel: r, container: container, context: context, thread: thread)
        #expect(again.thinkingEnabled)
        again.setThinkingEnabled(false)
        let reload = ModelContext(container)
        let id = thread.id
        let stored = try reload.fetch(FetchDescriptor<ThreadRecord>(predicate: #Predicate { $0.id == id })).first
        #expect(stored?.thinkingEnabled == false)
    }

    @Test func labelsKeepContrastOnTheTopWash() {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func luminance(_ rgb: (Double, Double, Double)) -> Double {
            0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
        }
        func hex(_ v: UInt32) -> (Double, Double, Double) {
            (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
        }
        func blend(_ top: (Double, Double, Double), _ base: (Double, Double, Double), _ alpha: Double) -> (Double, Double, Double) {
            (top.0 * alpha + base.0 * (1 - alpha), top.1 * alpha + base.1 * (1 - alpha), top.2 * alpha + base.2 * (1 - alpha))
        }
        func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
            let (x, y) = (luminance(a), luminance(b))
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        // Accent and label values from ARColor, over the system background at the darkest point of the wash.
        let light = blend(hex(0x0A0A0A), hex(0xFFFFFF), ARHomeWash.topOpacityLight)
        let dark = blend(hex(0xFAFAFA), hex(0x000000), ARHomeWash.topOpacityDark)
        #expect(contrast(hex(0x0A0A0A), light) >= 4.5)
        #expect(contrast(hex(0xFAFAFA), dark) >= 4.5)
    }

    @Test func washIsSubtleAndFadesBeforeTheMiddle() {
        #expect(ARHomeWash.topOpacityLight <= 0.14 && ARHomeWash.topOpacityDark <= 0.22)
        #expect(ARHomeWash.topOpacityDark > ARHomeWash.topOpacityLight)
        #expect(ARHomeWash.fadeEnd <= 0.5)
    }
}
