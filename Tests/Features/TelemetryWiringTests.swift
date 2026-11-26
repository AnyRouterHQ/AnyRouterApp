import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct TelemetryWiringTests {
    @Test func selectingAModelReportsOnlyItsSource() async {
        let registry = EngineRegistry()
        registry.register(ScriptedEngine())
        let recorder = RecordingTelemetry()
        let store = ModelStore(registry: registry, defaults: testDefaults(), telemetry: recorder)
        await store.refresh()
        store.select(store.models[0])
        #expect(recorder.events == [.modelSelected(source: .apple)])
    }

    @Test func sendingReportsTheSourceAndTheFirstTokenTimeOnce() async throws {
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["Hel", "lo"]))
        let recorder = RecordingTelemetry()
        let models = ModelStore(registry: registry, defaults: testDefaults(), telemetry: recorder)
        await models.refresh()
        let vm = ChatViewModel(
            thread: nil, context: ModelContext(try ModelContainer.anyRouter(inMemory: true)), registry: registry,
            settings: AppSettings(defaults: testDefaults()), models: models)
        vm.input = "a private prompt"
        await vm.send()?.value

        let events = recorder.events
        #expect(events.first == .messageSent(source: .apple))
        let firstTokens = events.filter { if case .firstTokenMs = $0 { true } else { false } }
        #expect(firstTokens.count == 1, "one first-token event per reply, not one per chunk")
        #expect(events.count == 2)
        for event in events {
            #expect(!event.logLine.contains("private"), "prompt text never reaches telemetry")
        }
    }

    @Test func sharingDiagnosticsFollowsTheBuildUntilTheUserChooses() {
        let defaults = testDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.shareDiagnostics == Diagnostics.isConfigured, "on by default only when a DSN exists")
        #expect(AppSettings.sharesDiagnostics(defaults: defaults) == Diagnostics.isConfigured)
        settings.shareDiagnostics = true
        #expect(AppSettings.sharesDiagnostics(defaults: defaults))
        settings.shareDiagnostics = false
        #expect(!AppSettings(defaults: defaults).shareDiagnostics, "the choice survives a relaunch")
    }
}
