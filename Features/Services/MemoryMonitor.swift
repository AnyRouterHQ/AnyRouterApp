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
    /// Whether the extended address space is signed into this install, read the same way.
    var extendedAddressingSigned: Bool? = nil
    /// The largest file the app can open in one piece right now. Nil where it is not measured (the Simulator).
    var mappableBytes: Int64? = nil
    /// What the fit check says here for each experimental catalog model, the big ones worth checking on a phone.
    var modelChecks: [ModelCheck] = []

    struct ModelCheck: Equatable, Sendable {
        var name: String
        var verdict: String
    }

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
    @ObservationIgnored private var backgroundTimer: Task<Void, Never>?
    /// Scene id to "is in the background".
    @ObservationIgnored private var scenes: [UUID: Bool] = [:]

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
        // Publish only a change: each write wakes every view that reads the monitor.
        let latest = read()
        if latest != readout { readout = latest }
        let id = await loaded()
        if id != loadedModelID { loadedModelID = id }
    }

    func unload() async {
        await unloadAll()
        await refresh()
    }

    /// Each window (scene) reports its phase. A model left loaded while every window is in the background is the
    /// first reason the system ends the app, so it is handed back after `delay`. Any window coming back cancels the
    /// wait, so a model another iPad window is using is never unloaded. A reply that is still running keeps its own
    /// reference to the model, so this never cuts it short.
    func scene(_ id: UUID, inBackground: Bool, after delay: Duration = .seconds(300)) {
        scenes[id] = inBackground
        reschedule(after: delay)
    }

    /// A window was closed: it no longer counts as using the model.
    func sceneClosed(_ id: UUID, after delay: Duration = .seconds(300)) {
        scenes[id] = nil
        reschedule(after: delay)
    }

    private func reschedule(after delay: Duration) {
        backgroundTimer?.cancel()
        backgroundTimer = nil
        guard !scenes.isEmpty, scenes.values.allSatisfy({ $0 }) else { return }
        backgroundTimer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }
}
