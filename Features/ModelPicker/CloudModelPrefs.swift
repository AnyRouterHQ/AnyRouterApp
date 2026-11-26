import Foundation

/// The person's own marks on cloud models: starred ones lead the lists, hidden ones stay out of them.
/// Models are keyed by wire id (`<provider>/<model>`), which the API keeps stable.
struct CloudModelPrefs: Codable, Equatable, Sendable {
    /// In the order they were starred.
    var starred: [String] = []
    var hidden: Set<String> = []

    func isStarred(_ model: ModelDescriptor) -> Bool { starred.contains(model.wireID) }
    func isHidden(_ model: ModelDescriptor) -> Bool { hidden.contains(model.wireID) }

    /// Starring a hidden model brings it back.
    mutating func toggleStar(_ wireID: String) {
        if let index = starred.firstIndex(of: wireID) {
            starred.remove(at: index)
        } else {
            starred.append(wireID)
            hidden.remove(wireID)
        }
    }

    /// Hiding a starred model takes the star away.
    mutating func hide(_ wireID: String) {
        hidden.insert(wireID)
        starred.removeAll { $0 == wireID }
    }

    mutating func unhide(_ wireID: String) {
        hidden.remove(wireID)
    }

    /// The cloud models the person hid, A to Z, for the list that brings them back.
    func hiddenModels(in models: [ModelDescriptor]) -> [ModelDescriptor] {
        models.filter { $0.source == .anyrouter && hidden.contains($0.wireID) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Starred models that AnyRouter still lists, for the Settings row.
    func starredCount(in models: [ModelDescriptor]) -> Int {
        models.filter { $0.source == .anyrouter && starred.contains($0.wireID) }.count
    }

    static let defaultsKey = "models.cloudPrefs.v1"

    /// Empty when nothing is saved or the saved data does not read back.
    static func load(from defaults: UserDefaults) -> CloudModelPrefs {
        guard let data = defaults.data(forKey: defaultsKey),
              let prefs = try? JSONDecoder().decode(CloudModelPrefs.self, from: data) else { return CloudModelPrefs() }
        return prefs
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
