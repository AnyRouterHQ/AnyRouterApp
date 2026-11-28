import Foundation

/// What the models folder holds, whatever the catalog says today. The disk is the source of truth: every folder under
/// `Models/` is a row, and the catalog only adds names. A model whose entry left the catalog still shows, with its size,
/// so it can be deleted; a download that never finished and files no record explains show too.
enum StorageInventoryLogic {
    struct Item: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            /// An installed model the catalog lists.
            case installed
            /// An installed model whose catalog entry is gone. It still loads from its manifest.
            case offCatalog
            /// A download that started and did not finish.
            case partial
            /// Files no manifest or download record explains, or a photo add-on whose model is gone.
            case orphan
        }

        /// The entry id when a manifest or download record names it, else the folder name.
        var id: String
        var name: String
        var bytes: Int64
        var kind: Kind
        /// Its own folder first, then the photo add-on that only it uses.
        var folders: [String]
        /// GGUF or MLX for an installed model, nil for anything else.
        var source: ModelSource?
        /// A download is moving files in this folder right now: it cannot be deleted from the storage list.
        var isRunning: Bool
    }

    static let offCatalogNote = "No longer in the catalog"

    /// One row per model or leftover, biggest first. `names` maps known entry ids (photo add-ons too) to their titles.
    /// `running` holds the folder names of downloads in flight.
    static func items(folders: [ModelFolder], names: [String: String], running: Set<String>) -> [Item] {
        let models = folders.filter { $0.manifest.map { !$0.isProjectorOnly } == true }
        var rows: [String: Item] = [:]
        var order: [String] = []
        func add(_ item: Item, folder: String) {
            rows[folder] = item
            order.append(folder)
        }
        for folder in folders {
            let isRunning = running.contains(folder.name)
            if let manifest = folder.manifest, !manifest.isProjectorOnly {
                let known = names[manifest.entryID]
                add(Item(
                    id: manifest.entryID, name: known ?? repoName(manifest.repo), bytes: folder.bytes,
                    kind: known == nil ? .offCatalog : .installed, folders: [folder.name],
                    source: manifest.format == .mlx ? .mlx : .gguf, isRunning: isRunning), folder: folder.name)
            } else if let manifest = folder.manifest {
                // A photo add-on: folded into its model below when exactly one installed model uses it.
                let users = models.filter { $0.manifest?.repo == manifest.repo }.count
                guard users != 1 else { continue }
                add(Item(
                    id: manifest.entryID, name: names[manifest.entryID] ?? "\(repoName(manifest.repo)) photo support",
                    bytes: folder.bytes, kind: users == 0 ? .orphan : .installed, folders: [folder.name], source: nil,
                    isRunning: isRunning), folder: folder.name)
            } else if !folder.hasManifest, let job = folder.job {
                add(Item(id: job.entry.id, name: names[job.entry.id] ?? job.entry.title, bytes: folder.bytes, kind: .partial,
                         folders: [folder.name], source: nil, isRunning: isRunning), folder: folder.name)
            } else {
                add(Item(id: folder.name, name: folder.name, bytes: folder.bytes, kind: .orphan, folders: [folder.name],
                         source: nil, isRunning: isRunning), folder: folder.name)
            }
        }
        // A photo add-on that exactly one installed model uses is part of that model: its size and its delete.
        for folder in folders {
            guard let manifest = folder.manifest, manifest.isProjectorOnly,
                  let user = models.first(where: { $0.manifest?.repo == manifest.repo }),
                  models.filter({ $0.manifest?.repo == manifest.repo }).count == 1,
                  var row = rows[user.name] else { continue }
            row.bytes += folder.bytes
            row.folders.append(folder.name)
            rows[user.name] = row
        }
        return order.compactMap { rows[$0] }.sorted { ($0.bytes, $1.name) > ($1.bytes, $0.name) }
    }

    /// "Qwen3-0.6B-GGUF" for "unsloth/Qwen3-0.6B-GGUF".
    static func repoName(_ repo: String) -> String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }

    /// The line under a row's name. Nil for a model the catalog lists.
    static func note(_ item: Item) -> String? {
        if item.isRunning { return "Downloading" }
        switch item.kind {
        case .installed: return nil
        case .offCatalog: return offCatalogNote
        case .partial: return "Unfinished download"
        case .orphan: return "Leftover files"
        }
    }

    /// Downloads that stopped part way and are not moving now.
    static func unfinished(_ items: [Item]) -> [Item] {
        items.filter { $0.kind == .partial && !$0.isRunning }
    }

    static func totalBytes(_ items: [Item]) -> Int64 {
        items.reduce(0) { $0 + max(0, $1.bytes) }
    }

    /// The storage row at the top of Local Models: "Models use 3.4 GB · 21.0 GB free".
    static func summary(_ items: [Item], freeBytes: Int64?) -> String {
        let used = "Models use \(FitFormat.gigabytes(totalBytes(items)))"
        return freeBytes.map { "\(used) · \(FitFormat.gigabytes($0)) free" } ?? used
    }

    /// Installed models the catalog no longer lists, as Local Models rows: they still load, and Delete works from disk.
    static func offCatalogEntries(_ items: [Item]) -> [LocalModelEntry] {
        items.compactMap { item in
            guard item.kind == .offCatalog, let source = item.source else { return nil }
            let descriptor = ModelDescriptor(
                id: item.id, source: source, displayName: item.name, contextLength: nil, capabilities: ["chat"],
                sizeBytes: item.bytes, isInstalled: true)
            return LocalModelEntry(
                descriptor: descriptor, summary: offCatalogNote, tags: [source == .mlx ? "mlx" : "gguf"], fit: .unknown,
                isUserAdded: false, isOffCatalog: true)
        }
    }

    /// Folders the launch clean-up removes: no manifest, no download record, no download in flight. That is a
    /// `.partial` or resume file a cancelled or forgotten job left, or an empty folder. A folder with a manifest is
    /// never named, even one this build cannot read.
    static func leftovers(_ folders: [ModelFolder], running: Set<String>) -> [String] {
        folders.filter { !$0.hasManifest && !$0.hasJob && !running.contains($0.name) }.map(\.name)
    }
}

extension LocalModelStorage {
    /// The launch clean-up: removes the folders `StorageInventoryLogic.leftovers` names and returns them. Safe to run again.
    func removeLeftovers(running: Set<String>) -> [String] {
        let names = StorageInventoryLogic.leftovers(folders(), running: running)
        for name in names { try? delete(folder: name) }
        return names
    }
}
