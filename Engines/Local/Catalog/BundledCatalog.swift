import Foundation

enum BundledCatalog {
    private final class Anchor {}

    /// Reads `catalog.json` from the app bundle. A missing or broken file is a build error, so this throws instead of returning an empty list.
    static func load(bundle: Bundle? = nil) throws -> CatalogDocument {
        let bundle = bundle ?? Bundle(for: Anchor.self)
        guard let url = bundle.url(forResource: "catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "catalog.json is missing from the app bundle."])
        }
        return try CatalogDocument.decode(Data(contentsOf: url))
    }
}
