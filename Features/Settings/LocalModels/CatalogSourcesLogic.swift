import Foundation

/// One place Local Models gets its list from: the shared catalog, or a Hugging Face repo the person added.
struct LocalCatalogSource: Identifiable, Hashable {
    enum Kind: Hashable { case sharedCatalog, huggingFaceRepo }

    var id: String
    var kind: Kind
    var title: String
    /// The catalog file's URL, or the repo id.
    var address: String
    /// "GGUF" or "MLX" for a repo. Nil for the catalog, which has both.
    var format: String?
    /// Commit or branch downloads come from. Nil means `main`.
    var revision: String?
    var models: [LocalModelEntry]

    var typeName: String {
        switch kind {
        case .sharedCatalog: "Model catalog"
        case .huggingFaceRepo: "Hugging Face repo"
        }
    }

    var isRemovable: Bool { kind == .huggingFaceRepo }
}

enum CatalogSourcesLogic {
    static let catalogID = "catalog"

    /// The shared catalog first, then one source per Hugging Face repo and format the person added.
    /// `remoteURL` is the custom catalog URL, empty when the default one is in use.
    static func sources(catalog: [LocalModelEntry], remoteURL: String, usesDevelopmentCatalog: Bool) -> [LocalCatalogSource] {
        let custom = !remoteURL.isEmpty
        let address = custom
            ? remoteURL
            : (usesDevelopmentCatalog ? CatalogSource.developmentURL : CatalogSource.productionURL).absoluteString
        let title = custom ? "Custom catalog" : (usesDevelopmentCatalog ? "AnyRouter catalog (development)" : "AnyRouter catalog")
        var result = [LocalCatalogSource(
            id: catalogID, kind: .sharedCatalog, title: title, address: address, format: nil, revision: nil,
            models: catalog.filter { !$0.isUserAdded })]

        var groups: [(key: String, entries: [LocalModelEntry])] = []
        for entry in catalog where entry.isUserAdded {
            let key = "\(entry.descriptor.source.rawValue)/\(entry.repo)"
            if let index = groups.firstIndex(where: { $0.key == key }) {
                groups[index].entries.append(entry)
            } else {
                groups.append((key, [entry]))
            }
        }
        for group in groups {
            let first = group.entries[0]
            result.append(LocalCatalogSource(
                id: group.key, kind: .huggingFaceRepo, title: first.repo, address: first.repo,
                format: HubListOptions.engineName(first.descriptor.source), revision: first.revision, models: group.entries))
        }
        return result
    }

    /// "Model catalog · 24 models", "GGUF · 3 models".
    static func subtitle(_ source: LocalCatalogSource) -> String {
        let count = source.models.count
        let models = "\(count) \(count == 1 ? "model" : "models")"
        return [source.format ?? source.typeName, models].joined(separator: " · ")
    }

    /// A source can be removed only when none of its models is installed: removing it would hide the files from the app.
    static func canRemove(_ source: LocalCatalogSource, state: (String) -> DownloadState) -> Bool {
        source.isRemovable && !source.models.contains { state($0.id) == .installed }
    }
}
