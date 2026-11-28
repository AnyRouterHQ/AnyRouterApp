import Foundation
import UIKit

/// "iPhone", "iPad" or "Mac", for sentences like "May not load on this iPhone".
enum DeviceName {
    @MainActor static var current: String {
        if ProcessInfo.processInfo.isiOSAppOnMac { return "Mac" }
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }
}

/// Words for the fit check: what to show on cards and picker rows. The estimate is a guess, so the words never block.
enum FitText {
    /// "6.88 GB" style size for a file. Same as the card's size label.
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func gigabytes(_ bytes: Int64) -> String { FitFormat.gigabytes(bytes) }

    private static func tokens(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic))
    }

    /// "needs ~8.1 GB". The tilde is always there: it is an estimate even when the metadata is exact.
    static func needs(_ detail: FitDetail) -> String {
        "needs ~\(gigabytes(detail.neededBytes))"
    }

    /// The badge on a card or row. `device` is "iPhone" or "iPad".
    static func badge(_ detail: FitDetail, device: String) -> String? {
        switch detail.verdict {
        case .fits: "Runs well"
        case .tight: "May be slow"
        case .wontFit: "May not load on this \(device)"
        case .unknown: nil
        }
    }

    /// One or two sentences under the card: what a tight or too-big model means here. Nil when it runs well.
    static func explanation(_ detail: FitDetail, device: String) -> String? {
        switch detail.verdict {
        case .fits, .unknown:
            return nil
        case .tight:
            var text = "On this \(device) it supports a \(tokens(detail.context))-token context and replies of up to \(tokens(detail.maxReply)) tokens."
            if detail.streamsFromStorage { text += " Weights stream from storage, so it is slower." }
            return text
        case .wontFit:
            if let mappable = detail.mappableBytes { return addressSpaceReason(mappableBytes: mappable) }
            if let ram = detail.streamsWithRAMGigabytes { return "Streaming it is planned for an \(device) with \(ram) GB of memory." }
            return "Needs ~\(gigabytes(detail.neededBytes)) · this \(device) has ~\(gigabytes(detail.budgetBytes)) for apps"
        }
    }

    /// Why a file bigger than the address space this install can map does not load, whatever the memory.
    static func addressSpaceReason(mappableBytes: Int64) -> String {
        "This install can open files up to \(gigabytes(mappableBytes)) at once. \(addressSpaceFix)"
    }

    /// What gives a larger address space.
    static let addressSpaceFix = "A build signed with the extended address space entitlement can open more."

    /// Shown once in Local Models when the increased memory limit is not signed into this install.
    static func memoryLimitNote(entitlementSigned: Bool?) -> String? {
        entitlementSigned == false
            ? "This install has the standard memory limit. TestFlight builds can load bigger models." : nil
    }

    /// Line for a loaded model: what the app uses and what is left.
    static func memoryLine(footprintBytes: Int64, availableBytes: Int64) -> String {
        "App memory \(gigabytes(footprintBytes)), \(gigabytes(availableBytes)) free"
    }
}
