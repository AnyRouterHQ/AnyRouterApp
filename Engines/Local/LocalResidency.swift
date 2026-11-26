import Foundation

/// One generation at a time: two contexts on a phone would double the KV-cache memory.
actor GenerationGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// How many generations wait for the gate. For tests.
    var waitingCount: Int { waiters.count }

    func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Takes the gate only when no generation holds it and none waits. For background work that must never delay a chat.
    func tryAcquire() -> Bool {
        guard !busy else { return false }
        busy = true
        return true
    }

    func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Keeps one local model loaded, whichever engine it belongs to. Loading is slow (seconds), so a second chat with the
/// same model reuses it. The key is the model's location and the time it was installed, so a download to the same
/// place replaces the weights.
actor ResidentModels {
    private struct Key: Equatable {
        var location: String
        var installedAt: Date?
        /// What the weights are (a llama.cpp model or an MLX container), so a hit always has the type the caller asks for.
        var kind: ObjectIdentifier
    }

    private struct Loaded: Sendable {
        var weights: any Sendable
    }

    private var current: (id: String, key: Key, weights: any Sendable)?
    /// A load in progress. A second request for the same weights joins it instead of loading them twice.
    /// An unload clears it: the load still hands its weights to the caller that asked, but nothing keeps them.
    private var loading: (id: String, key: Key, serial: Int, task: Task<Loaded, Error>)?
    private var lastSerial = 0
    private let telemetry: any Telemetry

    init(telemetry: any Telemetry = NoopTelemetry()) {
        self.telemetry = telemetry
    }

    /// Id of the loaded model, nil when none is.
    var loadedID: String? { current?.id }

    func weights<Weights: Sendable>(
        _ type: Weights.Type, at location: String, id: String, installedAt: Date? = nil, source: ModelSource,
        load: @escaping @Sendable () async throws -> Weights
    ) async throws -> Weights {
        let key = Key(location: location, installedAt: installedAt, kind: ObjectIdentifier(type))
        if let current, current.key == key { return current.weights as! Weights } // the key holds the type
        if let loading, loading.key == key { return try await loading.task.value.weights as! Weights }
        current = nil // free the old weights before the new ones load
        let started = ContinuousClock.now
        let task = Task.detached(priority: .userInitiated) { try Loaded(weights: await load()) }
        lastSerial += 1
        let serial = lastSerial
        loading = (id, key, serial, task)
        do {
            let loaded = try await task.value.weights as! Weights
            if loading?.serial == serial {
                loading = nil
                current = (id, key, loaded)
                telemetry.track(.engineLoadMs(TelemetryEvent.milliseconds(ContinuousClock.now - started), source: source))
            }
            return loaded
        } catch {
            if loading?.serial == serial { loading = nil }
            throw error
        }
    }

    /// Frees the weights, and drops a load in progress so that its weights are not kept.
    func unload() {
        current = nil
        loading = nil
    }

    /// The same, only when the weights belong to this model (it was deleted or replaced).
    func unload(ifID id: String) {
        if current?.id == id { current = nil }
        if loading?.id == id { loading = nil }
    }
}

/// What every local engine shares: one generation at a time, and one loaded model. Two engines with a gate and a cache
/// each would run two generations and keep two models in memory on a phone that has room for one.
final class LocalResidency: Sendable {
    let gate = GenerationGate()
    let models: ResidentModels

    init(telemetry: any Telemetry = NoopTelemetry()) {
        models = ResidentModels(telemetry: telemetry)
    }
}
