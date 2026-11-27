import Foundation
import Testing
@testable import AnyRouter

struct MemoryEntitlementTests {
    private static func be(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    private static func le(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    private static func entitlementsBlob(_ plist: [String: Any]) throws -> Data {
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return be(0xFADE_7171) + be(UInt32(8 + xml.count)) + xml
    }

    /// A code signature with an unrelated blob first, then the entitlements blob.
    private static func signature(_ plist: [String: Any]?) throws -> Data {
        let other = be(0xFADE_0C02) + be(8)
        var blobs: [(UInt32, Data)] = [(UInt32(0), other)]
        if let plist { blobs.append((5, try entitlementsBlob(plist))) }
        var out = be(0xFADE_0CC0)
        let headerSize = 12 + blobs.count * 8
        out += be(UInt32(headerSize + blobs.reduce(0) { $0 + $1.1.count })) + be(UInt32(blobs.count))
        var offset = headerSize
        for (type, blob) in blobs {
            out += be(type) + be(UInt32(offset))
            offset += blob.count
        }
        for (_, blob) in blobs { out += blob }
        return out
    }

    /// A 64-bit Mach-O header with a segment command and a code-signature command, then the signature at dataoff.
    private static func machO(signature: Data?) -> Data {
        let commands = 2
        let segment = le(0x19) + le(24) + Data(count: 16)
        let signatureOffset = 32 + 24 + 16 + 64
        let command = le(0x1D) + le(16) + le(UInt32(signatureOffset)) + le(UInt32(signature?.count ?? 0))
        var out = le(0xFEED_FACF) + le(0x0100_000C) + le(0) + le(2) + le(UInt32(commands)) + le(UInt32(24 + 16)) + le(0) + le(0)
        out += segment
        out += signature == nil ? Data(count: 16) : command
        out += Data(count: 64)
        if let signature { out += signature }
        return out
    }

    private func write(_ data: Data) throws -> URL {
        let url = makeTempDirectory().appending(path: "executable")
        try data.write(to: url)
        return url
    }

    @Test func theEntitlementIsFoundInASignedExecutable() throws {
        let signed = try Self.machO(signature: Self.signature([MemoryEntitlement.key: true, "application-identifier": "x"]))
        #expect(MemoryEntitlement.isSigned(executable: try write(signed)) == true)
    }

    @Test func aSignatureWithoutTheKeyOrWithItOffMeansTheStandardLimit() throws {
        let without = try Self.machO(signature: Self.signature(["application-identifier": "x"]))
        #expect(MemoryEntitlement.isSigned(executable: try write(without)) == false)
        let off = try Self.machO(signature: Self.signature([MemoryEntitlement.key: false]))
        #expect(MemoryEntitlement.isSigned(executable: try write(off)) == false)
    }

    @Test func anUnsignedOrUnreadableExecutableIsUnknownNotMissing() throws {
        #expect(MemoryEntitlement.isSigned(executable: try write(Self.machO(signature: nil))) == nil)
        #expect(MemoryEntitlement.isSigned(executable: try write(Data("not a binary at all, just text".utf8))) == nil)
        #expect(MemoryEntitlement.isSigned(executable: makeTempDirectory().appending(path: "missing")) == nil)
        let noEntitlementsBlob = try Self.machO(signature: Self.signature(nil))
        #expect(MemoryEntitlement.isSigned(executable: try write(noEntitlementsBlob)) == nil)
    }

    @Test func parsingFindsTheSignatureCommandAndRejectsBrokenInput() throws {
        let header = Self.machO(signature: Data(count: 100))
        let range = MemoryEntitlement.signatureRange(inMachOHeader: header)
        #expect(range?.offset == 32 + 24 + 16 + 64 && range?.size == 100)
        #expect(MemoryEntitlement.signatureRange(inMachOHeader: Data(count: 10)) == nil)
        #expect(MemoryEntitlement.signatureRange(inMachOHeader: Data(count: 64)) == nil, "no Mach-O magic")
        #expect(MemoryEntitlement.signatureRange(inMachOHeader: Self.machO(signature: nil).prefix(40)) == nil, "load commands cut short")
        #expect(MemoryEntitlement.entitlements(inSignature: Data(count: 4)) == nil)
        #expect(MemoryEntitlement.entitlements(inSignature: Data(count: 40)) == nil, "no signature magic")
        let broken = Self.be(0xFADE_0CC0) + Self.be(40) + Self.be(1) + Self.be(5) + Self.be(900)
        #expect(MemoryEntitlement.entitlements(inSignature: broken) == nil, "an offset past the end")
    }

    @Test func theRunningTestHostGivesAnAnswerWithoutCrashing() {
        // The Simulator test host is ad-hoc signed: any of true, false or nil is fine. It must not trap or hang.
        _ = MemoryEntitlement.isSignedForThisApp()
    }

    @Test func theExtendedAddressSpaceIsReadFromTheSameSignature() throws {
        let both = try Self.machO(signature: Self.signature([MemoryEntitlement.key: true, MemoryEntitlement.extendedAddressingKey: true]))
        let entitlements = try #require(MemoryEntitlement.signedEntitlements(executable: try write(both)))
        #expect(entitlements[MemoryEntitlement.extendedAddressingKey] as? Bool == true)
        #expect(MemoryEntitlement.extendedAddressingKey == "com.apple.developer.kernel.extended-virtual-addressing")
        // The Simulator's test host is not signed with entitlements: unknown, never a guess.
        _ = MemoryEntitlement.kernelEntitlementsForThisApp()
    }
}
