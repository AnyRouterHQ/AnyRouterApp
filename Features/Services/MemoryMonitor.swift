import Foundation
import Observation

/// What the app uses and how much is left before the system ends it.
struct MemoryReadout: Equatable, Sendable {
    var footprintBytes: Int64
    var availableBytes: Int64
}

/// Live memory of the app while a local model is loaded, with an unload action. The App layer supplies the readings and
/// the engines' unload, so the UI knows no engine types.
@MainActor @Observable
final class MemoryMonitor {
    private(set) var readout = MemoryReadout(footprintBytes: 0, availableBytes: 0)
    /// Id of the local model whose weights are in memory, nil when none.
    private(set) var loadedModelID: String?

    @ObservationIgnored private let read: @Sendable () -> MemoryReadout
    @ObservationIgnored private let loaded: @Sendable () async -> String?
    @ObservationIgnored private let unloadAll: @Sendable () async -> Void

    init(read: @escaping @Sendable () -> MemoryReadout,
         loaded: @escaping @Sendable () async -> String?,
         unload: @escaping @Sendable () async -> Void) {
        self.read = read
        self.loaded = loaded
        self.unloadAll = unload
        self.readout = read()
    }

    /// Reads nothing and has nothing loaded. For previews, tests and demo data.
    static func inert() -> MemoryMonitor {
        MemoryMonitor(read: { MemoryReadout(footprintBytes: 0, availableBytes: 0) }, loaded: { nil }, unload: {})
    }

    func refresh() async {
        readout = read()
        loadedModelID = await loaded()
    }

    func unload() async {
        await unloadAll()
        await refresh()
    }
}
