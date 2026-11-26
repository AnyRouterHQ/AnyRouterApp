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

    @Test func secondaryTextKeepsContrastOnEveryMeshColor() {
        func luminance(_ hex: UInt32) -> Double {
            func lin(_ v: UInt32) -> Double {
                let c = Double(v) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin((hex >> 16) & 0xFF) + 0.7152 * lin((hex >> 8) & 0xFF) + 0.0722 * lin(hex & 0xFF)
        }
        func contrast(_ a: UInt32, _ b: UInt32) -> Double {
            let (x, y) = (luminance(a), luminance(b))
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        for hex in ARHomePalette.lightMesh {
            #expect(contrast(ARHomePalette.lightSecondaryText, hex) >= 4.5, "light \(String(hex, radix: 16))")
            #expect(contrast(0x0A0A0A, hex) >= 4.5)
        }
        for hex in ARHomePalette.darkMesh {
            #expect(contrast(ARHomePalette.darkSecondaryText, hex) >= 4.5, "dark \(String(hex, radix: 16))")
            #expect(contrast(0xFAFAFA, hex) >= 4.5)
        }
    }

    @Test func meshIsCompleteAndMotionStaysSmall() {
        #expect(ARHomePalette.lightMesh.count == 9 && ARHomePalette.darkMesh.count == 9)
        let still = ARHomePalette.points(at: 0)
        #expect(still.count == 9)
        for t in stride(from: 0.0, to: 120.0, by: 7) {
            let p = ARHomePalette.points(at: t)
            #expect(p[0] == [0, 0] && p[8] == [1, 1])
            #expect(abs(p[4].x - 0.5) <= 0.07 + 0.001 && abs(p[4].y - 0.45) <= 0.06 + 0.001)
        }
    }
}
