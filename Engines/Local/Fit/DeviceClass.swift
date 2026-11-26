import Foundation

/// Whether the install carries `com.apple.developer.kernel.increased-memory-limit`. TestFlight and App Store builds do;
/// a sideloaded build re-signed with a free Apple ID does not and gets the standard per-app limit.
enum MemoryLimitKind: Sendable, CaseIterable {
    case standard
    case increased
}

/// A class of devices by installed RAM, with the memory an app can use on each. The model browser's recommendations
/// come from `FitPlanner` over these budgets; no model is listed by hand for any device.
enum DeviceClass: Int, Sendable, CaseIterable {
    case gb4 = 4, gb6 = 6, gb8 = 8, gb12 = 12, gb16 = 16

    /// Devices of this class, for docs and diagnostics.
    var examples: String {
        switch self {
        case .gb4: "iPhone 12, iPad mini 6"
        case .gb6: "iPhone 12 Pro and Pro Max, 13 Pro, 14, 15"
        case .gb8: "iPhone 15 Pro, 16, iPad mini (A17 Pro), iPad with M1 or M2"
        case .gb12: "iPhone 17 Pro and 18 Pro, iPad Air M3"
        case .gb16: "iPad Pro with M4 or M5"
        }
    }

    /// The most the app may use in total, in bytes. Standard limits are lower than half of RAM; the 12 GB figure was read
    /// from an iPhone 18 Pro (3.5 GB), the others are estimates from the same rule. With the increased-memory-limit
    /// entitlement the limit is about 70% of RAM.
    func limitBytes(_ kind: MemoryLimitKind) -> Int64 {
        let gigabytes: Double
        switch (self, kind) {
        case (.gb4, .standard): gigabytes = 1.8
        case (.gb6, .standard): gigabytes = 2.8
        case (.gb8, .standard): gigabytes = 3.4
        case (.gb12, .standard): gigabytes = 3.5
        case (.gb16, .standard): gigabytes = 4.5
        case (.gb4, .increased): gigabytes = 2.8
        case (.gb6, .increased): gigabytes = 4.2
        case (.gb8, .increased): gigabytes = 5.6
        case (.gb12, .increased): gigabytes = 8.4
        case (.gb16, .increased): gigabytes = 11.2
        }
        return Int64(gigabytes * 1_000_000_000)
    }

    /// What a model may use: the limit minus the app itself.
    func memory(_ kind: MemoryLimitKind) -> DeviceMemory {
        DeviceMemory(
            budgetBytes: max(0, limitBytes(kind) - DeviceMemory.appBaselineBytes),
            physicalBytes: Int64(rawValue) * 1_000_000_000)
    }

    /// The class of a device by the RAM the system reports, which is a little under the nominal size.
    static func nearest(physicalBytes: Int64) -> DeviceClass {
        switch physicalBytes {
        case ..<5_000_000_000: .gb4
        case ..<7_000_000_000: .gb6
        case ..<10_000_000_000: .gb8
        case ..<14_000_000_000: .gb12
        default: .gb16
        }
    }
}
