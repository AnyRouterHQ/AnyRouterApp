import Foundation
import Observation

/// What the app uses and how much is left before the system ends it.
struct MemoryReadout: Equatable, Sendable {
    var footprintBytes: Int64
    var availableBytes: Int64
}

/// Everything the memory budget is made of, for Settings > Diagnostics: read from the real device, nothing assumed.
struct MemoryDiagnostics: Equatable, Sendable {
    var footprintBytes: Int64
    var availableBytes: Int64
    var physicalBytes: Int64
    /// What a model may use: the process limit minus the app's own baseline.
    var budgetBytes: Int64
    /// Footprint plus available, the most this app may use. Zero when the system does not report it.
    var limitBytes: Int64
    /// Whether the increased memory limit is signed into this install. Nil when the signature cannot be read.
    var entitlementSigned: Bool?

    static let empty = MemoryDiagnostics(
        footprintBytes: 0, availableBytes: 0, physicalBytes: 0, budgetBytes: 0, limitBytes: 0, entitlementSigned: nil)
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
    @ObservationIgnored private let readDiagnostics: @Sendable () -> MemoryDiagnostics

    init(read: @escaping @Sendable () -> MemoryReadout,
         loaded: @escaping @Sendable () async -> String?,
         unload: @escaping @Sendable () async -> Void,
         diagnostics: @escaping @Sendable () -> MemoryDiagnostics = { .empty }) {
        self.read = read
        self.loaded = loaded
        self.unloadAll = unload
        self.readDiagnostics = diagnostics
        self.readout = read()
    }

    /// Reads nothing and has nothing loaded. For previews, tests and demo data.
    static func inert() -> MemoryMonitor {
        MemoryMonitor(read: { MemoryReadout(footprintBytes: 0, availableBytes: 0) }, loaded: { nil }, unload: {})
    }

    /// A full reading, taken off the main actor (it reads the app's code signature from disk).
    func diagnostics() async -> MemoryDiagnostics {
        let read = readDiagnostics
        return await Task.detached(priority: .utility) { read() }.value
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
