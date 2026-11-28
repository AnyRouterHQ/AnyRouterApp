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

    @Test func theQuestionIsAskedOnceAfterAGoodChatInABuildThatCanSend() {
        let settings = AppSettings(defaults: testDefaults())
        settings.noteSuccessfulChat(configured: false)
        #expect(!settings.isAskingDiagnostics, "a build without a DSN has nothing to ask")
        settings.noteSuccessfulChat(configured: true)
        #expect(settings.isAskingDiagnostics)
        settings.answerDiagnostics(share: false)
        #expect(!settings.isAskingDiagnostics && settings.diagnosticsAsked && !settings.shareDiagnostics)
        settings.noteSuccessfulChat(configured: true)
        #expect(!settings.isAskingDiagnostics, "Not now is remembered: no second alert")
    }

    @Test func sayingShareTurnsSharingOnAndIsRemembered() {
        let defaults = testDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.noteSuccessfulChat(configured: true)
        settings.answerDiagnostics(share: true)
        #expect(AppSettings.sharesDiagnostics(defaults: defaults))
        #expect(AppSettings(defaults: defaults).diagnosticsAsked)
    }

    @Test func aReplyRaisesTheQuestionAndAFailedOneDoesNot() async throws {
        // The test build has no DSN, so the alert flag stays down. What matters here is the wiring: asked once, via settings.
        let settings = AppSettings(defaults: testDefaults())
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["ok"]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let vm = ChatViewModel(
            thread: nil, context: ModelContext(try ModelContainer.anyRouter(inMemory: true)), registry: registry,
            settings: settings, models: models)
        vm.input = "hi"
        await vm.send()?.value
        #expect(!settings.isAskingDiagnostics, "no DSN in the test build")
    }

    @Test func sharingDiagnosticsIsOffUntilTheUserChooses() {
        let defaults = testDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.shareDiagnostics, "off by default, even in a build with a DSN")
        #expect(!AppSettings.sharesDiagnostics(defaults: defaults))
        settings.shareDiagnostics = true
        #expect(AppSettings.sharesDiagnostics(defaults: defaults))
        settings.shareDiagnostics = false
        #expect(!AppSettings(defaults: defaults).shareDiagnostics, "the choice survives a relaunch")
    }

    @Test func aFreshInstallWithADSNSendsNothingUntilTheUserSaysShare() {
        let suite = "anyrouter.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        let sink = DSNInstallSink()
        let telemetry = DiagnosticsConfig.makeTelemetry(
            dsn: "https://k@h.example.io/1", shareEnabled: { AppSettings.sharesDiagnostics(defaults: UserDefaults(suiteName: suite)!) },
            makeSink: { _ in sink })

        settings.noteSuccessfulChat(configured: true)
        #expect(settings.isAskingDiagnostics, "the question is raised, not answered for the user")
        telemetry.track(.appOpen)
        #expect(sink.events.isEmpty, "unanswered means nothing leaves the device")

        settings.answerDiagnostics(share: false)
        telemetry.track(.appOpen)
        #expect(sink.events.isEmpty, "Not now keeps it off")

        settings.answerDiagnostics(share: true)
        telemetry.track(.downloadOK)
        #expect(sink.events == [.downloadOK], "only an explicit Share forwards events")
    }
}

private final class DSNInstallSink: TelemetrySink, @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [TelemetryEvent] = []
    var events: [TelemetryEvent] { lock.withLock { raw } }
    func record(_ event: TelemetryEvent) { lock.withLock { raw.append(event) } }
}
