import Foundation

extension Bundle {
    /// A string from the Info.plist, or `fallback` when the key is missing.
    func infoString(_ key: String, default fallback: String) -> String {
        infoDictionary?[key] as? String ?? fallback
    }
}
