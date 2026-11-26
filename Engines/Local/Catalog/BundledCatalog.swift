import Foundation

enum BundledCatalog {
    private final class Anchor {}

    /// Reads `catalog/models.json` (bundled as `models.json`) from the app bundle. It is the offline fallback of the remote catalog. A missing or broken file is a build error, so this throws instead of returning an empty list.
    static func load(bundle: Bundle? = nil) throws -> CatalogDocument {
        let bundle = bundle ?? Bundle(for: Anchor.self)
        guard let url = bundle.url(forResource: "models", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "models.json is missing from the app bundle."])
        }
        return try CatalogDocument.decode(Data(contentsOf: url))
    }
}
