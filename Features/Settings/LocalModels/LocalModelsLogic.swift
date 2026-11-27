import Foundation

/// What the Local Models screen shows, with no UI: which models are installed, which ones to feature, which ones this
/// device cannot run and why, and what they all cost in storage. The fit verdicts come from `FitPlanner` through the hub.
enum LocalModelsLogic {
    static let disclaimer = "On-device models can give inaccurate or incomplete answers. Double-check important information. Models are provided by their publishers through Hugging Face."

    /// Installed models, A to Z.
    static func installed(_ catalog: [LocalModelEntry], state: (String) -> DownloadState) -> [LocalModelEntry] {
        catalog.filter { state($0.id) == .installed }
            .sorted { $0.descriptor.displayName.localizedCaseInsensitiveCompare($1.descriptor.displayName) == .orderedAscending }
    }

    struct Storage: Equatable {
        var modelCount: Int
        var usedBytes: Int64
        var freeBytes: Int64?
    }

    /// Sum of the installed models' file sizes. A model with no known size counts as zero.
    static func storage(installed: [LocalModelEntry], freeBytes: Int64?) -> Storage {
        Storage(
            modelCount: installed.count,
            usedBytes: installed.reduce(0) { $0 + max(0, $1.descriptor.sizeBytes ?? 0) },
            freeBytes: freeBytes)
    }

    /// The best size of each family for this device, top picks first, without what is already installed
    /// (the Installed section lists those). Downloads in flight stay, so their progress shows where Get was.
    /// An experimental family is never a pick: its first size that runs here follows the picks, outside the limit, so a
    /// device that can run it still finds it and one that cannot never sees it.
    static func featured(families: [LocalModelFamily], state: (String) -> DownloadState, limit: Int = 5) -> [LocalModelEntry] {
        let (experimental, regular) = (families.filter(FamilyLogic.isExperimental), families.filter { !FamilyLogic.isExperimental($0) })
        let ranked = FamilyLogic.recommendedEntries(from: regular, limit: regular.count)
        let picks = ranked.filter { state($0.id) != .installed }.prefix(max(0, limit))
        let tries = experimental.compactMap { family in
            family.variants.first { FamilyLogic.canRun($0) && state($0.id) != .installed }
        }
        return Array(picks) + tries
    }

    struct UnavailableModel: Identifiable, Equatable {
        var entry: LocalModelEntry
        /// A plain sentence: "Needs about 3.9 GB, this iPhone allows 3.2 GB."
        var reason: String
        var id: String { entry.id }
    }

    /// Catalog sizes this device cannot run, in catalog order. Installed models are not listed: they run or they are
    /// the person's to delete. `device` is "iPhone" or "iPad".
    static func unavailable(catalog: [LocalModelEntry], state: (String) -> DownloadState, device: String) -> [UnavailableModel] {
        catalog.compactMap { entry in
            guard !entry.isDeprecated, state(entry.id) != .installed, let reason = reason(for: entry, device: device)
            else { return nil }
            return UnavailableModel(entry: entry, reason: reason)
        }
    }

    /// Why one model cannot run here, or nil when it can (a tight fit still runs).
    static func reason(for entry: LocalModelEntry, device: String) -> String? {
        if let blocked = entry.unavailableReason { return blocked }
        if let detail = entry.fitDetail, detail.verdict == .wontFit {
            if let mappable = detail.mappableBytes { return FitText.addressSpaceReason(mappableBytes: mappable) }
            if let gigabytes = detail.streamsWithRAMGigabytes { return "Needs an \(device) with \(gigabytes) GB of memory." }
            return "Needs about \(FitFormat.gigabytes(detail.neededBytes)), this \(device) allows \(FitFormat.gigabytes(detail.budgetBytes))."
        }
        return entry.fit == .wontFit ? "Too big for this \(device)." : nil
    }

    /// The last row of Featured.
    static func unavailableTitle(count: Int, device: String) -> String {
        "Not available on this \(device) (\(count))"
    }

    /// "GGUF · 4B · Q4_K_M · 2.5 GB": what the file is, without the memory estimate that the reason already gives.
    static func fileLine(_ entry: LocalModelEntry) -> String {
        var parts = [HubListOptions.engineName(entry.descriptor.source)]
        parts += [entry.parameters, entry.quantization].compactMap { $0 }
        if let size = HubLogic.sizeText(entry.descriptor.sizeBytes) { parts.append(size) }
        return parts.joined(separator: " · ")
    }

    /// One sentence for the Delete All Models confirmation.
    static func deleteAllMessage(_ storage: Storage, device: String) -> String {
        let noun = storage.modelCount == 1 ? "model" : "models"
        return "This removes \(storage.modelCount) \(noun) (\(FitFormat.gigabytes(storage.usedBytes))) from this \(device). You can download them again later."
    }

    /// Apple Intelligence as the System row shows it: ready, or why not.
    static func appleStatus(_ model: ModelDescriptor) -> String {
        if model.isInstalled { return "Available · Built in" }
        return model.summary.map { "Not available · \($0)" } ?? "Not available on this device"
    }
}
