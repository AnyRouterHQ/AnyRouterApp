import Foundation
import UIKit

/// "iPhone" or "iPad", for sentences like "Too big for this iPhone".
enum DeviceName {
    @MainActor static var current: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }
}

/// Words for the fit check: what to show on cards, picker rows and download warnings.
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
        case .wontFit: "Too big for this \(device)"
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
            return "Needs ~\(gigabytes(detail.neededBytes)) · this \(device) has ~\(gigabytes(detail.budgetBytes)) for apps"
        }
    }

    /// The warning before a download that will not run, or nil when there is nothing to warn about.
    static func downloadWarning(_ detail: FitDetail?, sizeText: String?, device: String) -> String? {
        guard let detail, detail.verdict == .wontFit else { return nil }
        let size = sizeText.map { " (\($0))" } ?? ""
        return "This model\(size) needs about \(gigabytes(detail.neededBytes)) of memory. This \(device) can give about \(gigabytes(detail.budgetBytes)), so it will not load."
    }

    /// Shown once in Manage models when the increased memory limit is not signed into this install.
    static func memoryLimitNote(entitlementSigned: Bool?) -> String? {
        entitlementSigned == false
            ? "This install has the standard memory limit. TestFlight builds can load bigger models." : nil
    }

    /// Line for a loaded model: what the app uses and what is left.
    static func memoryLine(footprintBytes: Int64, availableBytes: Int64) -> String {
        "App memory \(gigabytes(footprintBytes)), \(gigabytes(availableBytes)) free"
    }
}
