import Darwin
import Foundation
import os

/// Reads this process's memory from the system. The fit math itself lives in `FitPlanner` and takes plain numbers.
enum MemoryReading {
    /// Memory the system charges to this app (`phys_footprint`, what jetsam compares to the limit).
    static func footprintBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    /// Bytes this app can still allocate before the system ends it. Counts the increased-memory-limit entitlement.
    /// Zero where the system does not report it (the Simulator may).
    static func availableBytes() -> Int64 {
        Int64(os_proc_available_memory())
    }

    static func physicalBytes() -> Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }

    /// The largest single region this process can still map, found by reserving address space (no memory, nothing the
    /// system charges) and releasing it at once. llama.cpp maps a model file in one piece, so a bigger file cannot load.
    /// Nil on the Simulator, whose address space is the Mac's.
    static func largestMappableBytes() -> Int64? {
        #if targetEnvironment(simulator)
        return nil
        #else
        return largestReservable(upTo: 64 << 30, step: 256 << 20, reserve: canReserve)
        #endif
    }

    /// Whether `bytes` of address space can be reserved in one piece right now.
    static func canReserve(_ bytes: Int64) -> Bool {
        let region = mmap(nil, Int(bytes), PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0)
        guard let region, region != UnsafeMutableRawPointer(bitPattern: -1) else { return false }
        munmap(region, Int(bytes))
        return true
    }

    /// The largest multiple of `step` up to `limit` that `reserve` accepts, by binary search; 0 when not even one step.
    static func largestReservable(upTo limit: Int64, step: Int64, reserve: (Int64) -> Bool) -> Int64 {
        var low: Int64 = 0
        var high = limit / step
        while low < high {
            let middle = (low + high + 1) / 2
            if reserve(middle * step) { low = middle } else { high = middle - 1 }
        }
        return low * step
    }
}

/// A reading for the UI: how much the app uses and how much is left.
struct MemorySnapshot: Equatable, Sendable {
    var footprintBytes: Int64
    var availableBytes: Int64
    var physicalBytes: Int64

    static func read() -> MemorySnapshot {
        MemorySnapshot(
            footprintBytes: MemoryReading.footprintBytes(), availableBytes: MemoryReading.availableBytes(),
            physicalBytes: MemoryReading.physicalBytes())
    }

    /// The most this app may use in total: what it uses now plus what is left. Zero where the system does not report it.
    var processLimitBytes: Int64 { availableBytes > 0 ? footprintBytes + availableBytes : 0 }

    /// What a model may use. The process limit is what the app uses now plus what is left; a loaded model is already
    /// part of the first term, so the budget does not shrink while one is loaded. Without a reading, half of RAM:
    /// iOS ends a foreground app near that.
    var deviceMemory: DeviceMemory {
        let limit = availableBytes > 0 ? footprintBytes + availableBytes : physicalBytes / 2
        return DeviceMemory(budgetBytes: max(0, limit - DeviceMemory.appBaselineBytes), physicalBytes: physicalBytes)
    }
}

extension DeviceMemory {
    /// `mappable` also measures the address space (a few reservations, no memory), for checks before a download.
    static func current(mappable: Bool = false) -> DeviceMemory {
        var memory = MemorySnapshot.read().deviceMemory
        if mappable { memory.mappableBytes = MemoryReading.largestMappableBytes() }
        return memory
    }
}
