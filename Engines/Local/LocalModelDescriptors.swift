import Foundation

extension CatalogEntry {
    /// The picker/registry view of a catalog entry.
    /// `imageInput` is whether the installed copy can take photos: it has its projector and the device has room for it.
    /// Nil leaves the catalog's capabilities as they are.
    func descriptor(isInstalled: Bool, sizeBytes: Int64? = nil, imageInput: Bool? = nil) -> ModelDescriptor {
        let name = (format == .gguf && quantization != nil) ? "\(title) (\(quantization ?? ""))" : title
        var capabilities = self.capabilities
        if imageInput == false { capabilities.remove("vision") }
        return ModelDescriptor(
            id: id, source: format == .gguf ? .gguf : .mlx, displayName: name,
            contextLength: contextLength, capabilities: capabilities,
            sizeBytes: sizeBytes ?? self.sizeBytes, isInstalled: isInstalled)
    }
}

enum LocalModelDescriptors {
    /// Installed models of one format. Names and capabilities come from the catalog when it knows the entry;
    /// a model whose catalog entry is gone (user removed the repo) still shows, named after its repo.
    static func installed(
        format: LocalModelFormat, storage: LocalModelStorage, catalog: [CatalogEntry],
        memory: DeviceMemory = .current()
    ) -> [ModelDescriptor] {
        let known = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return storage.installedManifests().filter { $0.format == format }.map { manifest in
            let onDisk = manifest.files.reduce(Int64(0)) { $0 + $1.size }
            if let entry = known[manifest.entryID] {
                // Photos need the projector on disk and room for it in memory.
                let hasProjector = manifest.files.contains { VisionInput.isProjector(path: $0.path) }
                let roomForIt = entry.memoryProfile.map { FitPlanner.imageInput($0, memory: memory) != .wontFit } ?? false
                return entry.descriptor(
                    isInstalled: true, sizeBytes: onDisk, imageInput: entry.vision != nil && hasProjector && roomForIt)
            }
            let name = manifest.repo.split(separator: "/").last.map(String.init) ?? manifest.repo
            return ModelDescriptor(
                id: manifest.entryID, source: format == .gguf ? .gguf : .mlx, displayName: name,
                contextLength: nil, capabilities: ["chat"], sizeBytes: onDisk, isInstalled: true)
        }
    }
}
