import Foundation

/// Whether the installed app is signed with `com.apple.developer.kernel.increased-memory-limit`. Sideloading tools that
/// re-sign with a free Apple ID drop it, and the app then gets the standard per-app limit (about half of RAM, less on
/// some devices). The entitlement is read from the code signature of the app's own executable.
enum MemoryEntitlement {
    static let key = "com.apple.developer.kernel.increased-memory-limit"

    private static let loadCommandSignature: UInt32 = 0x1D
    private static let machO64Magic: UInt32 = 0xFEED_FACF
    private static let superBlobMagic: UInt32 = 0xFADE_0CC0
    private static let entitlementsBlobMagic: UInt32 = 0xFADE_7171

    /// Where the code signature sits in a thin 64-bit Mach-O, from its header and load commands.
    static func signatureRange(inMachOHeader data: Data) -> (offset: Int, size: Int)? {
        guard data.count >= 32, littleEndian32(data, 0) == machO64Magic else { return nil }
        var position = 32
        for _ in 0..<littleEndian32(data, 16) {
            guard position + 8 <= data.count else { return nil }
            let command = littleEndian32(data, position)
            let size = Int(littleEndian32(data, position + 4))
            guard size >= 8 else { return nil }
            if command == loadCommandSignature {
                guard position + 16 <= data.count else { return nil }
                return (Int(littleEndian32(data, position + 8)), Int(littleEndian32(data, position + 12)))
            }
            position += size
        }
        return nil
    }

    /// The entitlements dictionary inside a code-signature blob, or nil when there is none.
    static func entitlements(inSignature blob: Data) -> [String: Any]? {
        guard blob.count >= 12, bigEndian32(blob, 0) == superBlobMagic else { return nil }
        let count = Int(bigEndian32(blob, 8))
        for index in 0..<min(count, 64) {
            let entry = 12 + index * 8
            guard entry + 8 <= blob.count else { return nil }
            let offset = Int(bigEndian32(blob, entry + 4))
            guard offset + 8 <= blob.count, bigEndian32(blob, offset) == entitlementsBlobMagic else { continue }
            let length = Int(bigEndian32(blob, offset + 4))
            guard length >= 8, offset + length <= blob.count else { return nil }
            let plist = blob.subdata(in: (offset + 8)..<(offset + length))
            return (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any]
        }
        return nil
    }

    /// True or false when the executable's signature says; nil when it has no readable signature (unsigned builds,
    /// the Simulator).
    static func isSigned(executable: URL) -> Bool? {
        guard let handle = try? FileHandle(forReadingFrom: executable) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 32), head.count == 32,
              littleEndian32(head, 0) == machO64Magic,
              let commands = try? handle.read(upToCount: Int(littleEndian32(head, 20))),
              let range = signatureRange(inMachOHeader: head + commands),
              range.size > 0, range.size < 1 << 26,
              (try? handle.seek(toOffset: UInt64(range.offset))) != nil,
              let blob = try? handle.read(upToCount: range.size),
              let entitlements = entitlements(inSignature: blob)
        else { return nil }
        return (entitlements[key] as? Bool) == true
    }

    /// The running app. Reads a few hundred KB once; call off the main actor.
    static func isSignedForThisApp() -> Bool? {
        Bundle.main.executableURL.flatMap { isSigned(executable: $0) }
    }

    private static func littleEndian32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: data.startIndex + offset, as: UInt32.self)) }
    }

    private static func bigEndian32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: data.startIndex + offset, as: UInt32.self)) }
    }
}
