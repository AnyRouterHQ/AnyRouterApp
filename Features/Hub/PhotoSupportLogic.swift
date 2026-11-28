import Foundation

/// What a model's page shows for its optional photo support: one status line when a download is under way and the
/// action that fits the state. The state is the download state of the add-on (`CatalogEntry.photoAddOn`).
struct PhotoSupportRow: Equatable {
    enum Action: Equatable {
        case add(title: String)
        case resume
        case cancel
        case remove

        var title: String {
            switch self {
            case .add(let title): title
            case .resume: "Resume"
            case .cancel: "Cancel download"
            case .remove: PhotoSupportLogic.removeTitle
            }
        }
    }

    struct Status: Equatable {
        var label: String
        var value: String?
    }

    /// Shown while the add-on downloads, pauses or verifies.
    var status: Status?
    var failure: String?
    var actions: [Action]
}

enum PhotoSupportLogic {
    static let removeTitle = "Remove photo support"

    /// "Add photo support · 346 MB". The size is left out when the catalog has none.
    static func addTitle(sizeBytes: Int64?) -> String {
        guard let size = sizeText(sizeBytes) else { return "Add photo support" }
        return "Add photo support · \(size)"
    }

    /// Whole megabytes below a gigabyte: the system formatter keeps a decimal there ("345.9 MB"), a row title wants "346 MB".
    static func sizeText(_ bytes: Int64?) -> String? {
        guard let bytes, bytes < 1_000_000_000 else { return HubLogic.sizeText(bytes) }
        return "\(Int((Double(bytes) / 1_000_000).rounded())) MB"
    }

    static func row(state: DownloadState, sizeBytes: Int64?) -> PhotoSupportRow {
        let add = PhotoSupportRow.Action.add(title: addTitle(sizeBytes: sizeBytes))
        switch state {
        case .notInstalled:
            return PhotoSupportRow(actions: [add])
        case .failed(let message):
            return PhotoSupportRow(failure: message, actions: [add])
        case .downloading(let progress):
            return PhotoSupportRow(status: .init(label: "Adding photo support", value: HubLogic.percent(progress)), actions: [.cancel])
        case .paused(let progress):
            return PhotoSupportRow(status: .init(label: "Photo support paused", value: HubLogic.percent(progress)), actions: [.resume, .cancel])
        case .verifying:
            return PhotoSupportRow(status: .init(label: "Verifying photo support", value: nil), actions: [])
        case .installed:
            return PhotoSupportRow(actions: [.remove])
        }
    }

    /// Whether the model reads photos now. The device has room for the projector, and a projector that is an optional
    /// add-on is installed (`addOnInstalled` is nil when the projector is part of the model's download).
    static func readsPhotos(roomForProjector: Bool, addOnInstalled: Bool?) -> Bool {
        roomForProjector && (addOnInstalled ?? true)
    }

    /// The model's capabilities with "vision" set to what it reads now.
    static func capabilities(_ base: Set<String>, readsPhotos: Bool) -> Set<String> {
        var capabilities = base
        if readsPhotos { capabilities.insert("vision") } else { capabilities.remove("vision") }
        return capabilities
    }
}
