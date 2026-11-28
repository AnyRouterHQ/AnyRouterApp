import os

/// Signposts for the performance baseline (PLAN § Native UX & performance). Free when nothing is listening.
/// Names are read by `UITests/PerformanceTests.swift`; rename them in both places.
enum Perf {
    static let signposter = OSSignposter(subsystem: "oneni.anyr.app", category: "perf")

    /// Time from process start of our code to the first usable model. Begun in `ModelStore.init`, ended once.
    @MainActor private static var modelsState: OSSignpostIntervalState?

    @MainActor static func beginModels() {
        modelsState = signposter.beginInterval("models.firstUsable")
    }

    @MainActor static func endModels() {
        guard let state = modelsState else { return }
        signposter.endInterval("models.firstUsable", state)
        modelsState = nil
    }
}
