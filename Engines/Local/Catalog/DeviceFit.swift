import Foundation

enum FitVerdict: String, Sendable {
    case fits
    case tight
    case tooLarge
}

/// Will a model of a given size run on this device? RAM only, no GPU or disk checks.
struct DeviceFit: Sendable {
    var physicalMemory: UInt64

    init(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        self.physicalMemory = physicalMemory
    }

    /// Weights plus 20% and 512 MB for the KV cache and runtime buffers.
    func workingSetBytes(modelBytes: Int64) -> UInt64 {
        let weights = UInt64(max(modelBytes, 0))
        return weights + weights / 5 + 512 * 1024 * 1024
    }

    /// iOS kills a foreground app near half of physical RAM, so the thresholds sit under that:
    /// up to 40% of RAM fits, up to 60% is tight, above is too large.
    func verdict(modelBytes: Int64) -> FitVerdict {
        guard physicalMemory > 0 else { return .tooLarge }
        let ratio = Double(workingSetBytes(modelBytes: modelBytes)) / Double(physicalMemory)
        if ratio <= 0.40 { return .fits }
        if ratio <= 0.60 { return .tight }
        return .tooLarge
    }
}
