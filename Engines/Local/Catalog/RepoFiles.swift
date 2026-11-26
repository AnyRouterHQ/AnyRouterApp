import Foundation

/// A GGUF file the user can pick inside a repo.
struct GGUFChoice: Hashable, Sendable {
    var path: String
    var sizeBytes: Int64
    var quantization: String?
}

/// Turns a repo listing into what the app can download.
enum RepoFiles {
    /// Best first. Q4_K_M is the usual quality/size balance on a phone.
    static let preferredQuantizations = ["Q4_K_M", "Q4_K_S", "Q4_0", "Q5_K_M", "Q5_K_S", "Q6_K", "Q3_K_M", "Q8_0", "IQ4_XS"]

    private static let quantPattern =
        #"(?i)(?<![A-Za-z0-9])((?:IQ|Q)\d(?:_[A-Z0-9]+)*|BF16|F16|F32)(?![A-Za-z0-9])"#

    static func quantization(inFileName name: String) -> String? {
        guard let range = name.range(of: quantPattern, options: .regularExpression) else { return nil }
        return String(name[range]).uppercased()
    }

    /// Single-file GGUF weights. Vision projectors (`mmproj`) and split shards (`-00001-of-00003`) are left out:
    /// a projector is not a chat model, and shards need every part.
    static func ggufChoices(_ files: [HFFile]) -> [GGUFChoice] {
        files.compactMap { file in
            let name = (file.path as NSString).lastPathComponent
            guard name.lowercased().hasSuffix(".gguf"),
                  !name.lowercased().contains("mmproj"),
                  name.range(of: #"-\d{5}-of-\d{5}"#, options: .regularExpression) == nil
            else { return nil }
            return GGUFChoice(path: file.path, sizeBytes: file.size, quantization: quantization(inFileName: name))
        }
        .sorted { $0.sizeBytes < $1.sizeBytes }
    }

    /// The preferred quantization that is not too large for the device, else the smallest file.
    static func defaultChoice(_ choices: [GGUFChoice], fit: DeviceFit = DeviceFit()) -> GGUFChoice? {
        for quant in preferredQuantizations {
            if let match = choices.first(where: { $0.quantization == quant }),
               fit.verdict(modelBytes: match.sizeBytes) != .tooLarge {
                return match
            }
        }
        return choices.min { $0.sizeBytes < $1.sizeBytes }
    }

    private static let mlxExtensions: Set<String> = ["safetensors", "json", "model", "txt", "jinja", "tiktoken"]

    /// What an MLX snapshot needs: weights, configs, tokenizer, chat template. No README, no git files.
    static func mlxSnapshotFiles(_ files: [HFFile]) -> [HFFile] {
        files.filter { file in
            let ext = (file.path as NSString).pathExtension.lowercased()
            return mlxExtensions.contains(ext) && !(file.path as NSString).lastPathComponent.hasPrefix(".")
        }
    }

    /// The files to download for an entry, picked from the repo listing at its revision.
    static func downloadPlan(for entry: CatalogEntry, files: [HFFile]) throws -> [HFFile] {
        switch entry.format {
        case .gguf:
            guard let match = files.first(where: { $0.path == entry.file }) else {
                throw LocalModelError.notFound(entry.file ?? entry.repo)
            }
            return [match]
        case .mlx:
            let snapshot = mlxSnapshotFiles(files)
            guard snapshot.contains(where: { $0.path.hasSuffix(".safetensors") }) else {
                throw LocalModelError.noFiles(entry.repo)
            }
            return snapshot
        }
    }

    /// Catalog entries for a repo the user added: one per GGUF file, or one for the MLX snapshot.
    static func entries(
        repo: String, format: LocalModelFormat, files: [HFFile], revision: String? = nil
    ) throws -> [CatalogEntry] {
        guard HuggingFaceAPI.isValidRepo(repo) else { throw LocalModelError.invalidRepo(repo) }
        let name = String(repo.split(separator: "/").last ?? "")
        switch format {
        case .gguf:
            let choices = ggufChoices(files)
            guard !choices.isEmpty else { throw LocalModelError.noFiles(repo) }
            return choices.map { choice in
                CatalogEntry(
                    repo: repo, format: .gguf, file: choice.path, title: name,
                    quantization: choice.quantization, sizeBytes: choice.sizeBytes,
                    revision: revision, origin: .user)
            }
        case .mlx:
            let snapshot = mlxSnapshotFiles(files)
            guard snapshot.contains(where: { $0.path.hasSuffix(".safetensors") }) else {
                throw LocalModelError.noFiles(repo)
            }
            return [CatalogEntry(
                repo: repo, format: .mlx, title: name,
                sizeBytes: snapshot.reduce(0) { $0 + $1.size }, revision: revision, origin: .user)]
        }
    }
}
