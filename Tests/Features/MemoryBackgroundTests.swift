import Foundation
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
        memory.appInBackground(true, after: .milliseconds(30))
        #expect(await waitUntil { unloaded.value })
    }

    @Test func comingBackBeforeTheDelayKeepsTheModel() async {
        let unloaded = Flag()
        let memory = monitor(unloaded: unloaded)
        memory.appInBackground(true, after: .milliseconds(150))
        memory.appInBackground(false)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(!unloaded.value)
    }

    @Test func goingToTheBackgroundAgainRestartsTheWait() async {
        let unloaded = Flag()
        let memory = monitor(unloaded: unloaded)
        memory.appInBackground(true, after: .milliseconds(200))
        try? await Task.sleep(for: .milliseconds(120))
        memory.appInBackground(true, after: .milliseconds(200))
        try? await Task.sleep(for: .milliseconds(120))
        #expect(!unloaded.value)
        #expect(await waitUntil { unloaded.value })
    }
}
