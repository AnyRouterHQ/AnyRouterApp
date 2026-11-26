import Foundation
import Observation
import Testing
@testable import AnyRouter

@MainActor
struct MemoryBackgroundTests {
    private func monitor(unloaded: Flag) -> MemoryMonitor {
        MemoryMonitor(
            read: { MemoryReadout(footprintBytes: 0, availableBytes: 0) },
            loaded: { nil },
            unload: { unloaded.value = true })
    }

    @Test func aModelLeftLoadedInTheBackgroundIsUnloadedAfterTheDelay() async {
        let unloaded = Flag()
        let memory = monitor(unloaded: unloaded)
        memory.scene(UUID(), inBackground: true, after: .milliseconds(30))
        #expect(await waitUntil { unloaded.value })
    }

    @Test func comingBackBeforeTheDelayKeepsTheModel() async {
        let unloaded = Flag()
        let memory = monitor(unloaded: unloaded)
        let scene = UUID()
        memory.scene(scene, inBackground: true, after: .milliseconds(150))
        memory.scene(scene, inBackground: false)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(!unloaded.value)
    }

    @Test func goingToTheBackgroundAgainRestartsTheWait() async {
        let unloaded = Flag()
        let memory = monitor(unloaded: unloaded)
        let scene = UUID()
        memory.scene(scene, inBackground: true, after: .milliseconds(200))
        try? await Task.sleep(for: .milliseconds(120))
        memory.scene(scene, inBackground: true, after: .milliseconds(200))
        try? await Task.sleep(for: .milliseconds(120))
        #expect(!unloaded.value)
        #expect(await waitUntil { unloaded.value })
    }

    /// iPad: a second window in front still uses the model.
    @Test func aModelIsKeptWhileAnotherWindowIsActive() async {
        let unloaded = Flag()
        let memory = monitor(unloaded: unloaded)
        let first = UUID()
        let second = UUID()
        memory.scene(second, inBackground: false)
        memory.scene(first, inBackground: true, after: .milliseconds(30))
        try? await Task.sleep(for: .milliseconds(300))
        #expect(!unloaded.value)
    }

    @Test func closingTheActiveWindowLeavesOnlyBackgroundOnesSoTheModelIsUnloaded() async {
        let unloaded = Flag()
        let memory = monitor(unloaded: unloaded)
        let first = UUID()
        let second = UUID()
        memory.scene(second, inBackground: false)
        memory.scene(first, inBackground: true, after: .milliseconds(30))
        memory.sceneClosed(second, after: .milliseconds(30))
        #expect(await waitUntil { unloaded.value })
    }

    /// A refresh that finds nothing new must not wake the views that watch the monitor.
    @Test func aRefreshWithNothingNewPublishesNothing() async {
        let memory = monitor(unloaded: Flag())
        let changed = Flag()
        withObservationTracking {
            _ = memory.readout
            _ = memory.loadedModelID
        } onChange: {
            changed.value = true
        }
        await memory.refresh()
        #expect(!changed.value)
    }

    @Test func aRefreshThatFindsAChangePublishesIt() async {
        let loaded = Flag()
        let memory = MemoryMonitor(
            read: { MemoryReadout(footprintBytes: 1, availableBytes: 2) },
            loaded: { loaded.value ? "gguf/x" : nil },
            unload: {})
        #expect(memory.loadedModelID == nil)
        loaded.value = true
        await memory.refresh()
        #expect(memory.loadedModelID == "gguf/x")
    }
}
