import Foundation
import SwiftData

/// Opens the chat store. A store that cannot be opened is moved aside, never deleted, and a new one is started,
/// so a bad update or a corrupt file costs the user a note instead of a crash at launch.
enum StoreOpening {
    struct Outcome {
        var container: ModelContainer
        /// One-time message for the user when the store had to be replaced.
        var note: String?
    }

    static var defaultStoreURL: URL { URL.applicationSupportDirectory.appending(path: "default.store") }

    /// `make` builds a container at a URL; `nil` asks for an in-memory one (the last resort).
    static func open(
        at url: URL = defaultStoreURL,
        make: (URL?) throws -> ModelContainer = { try ModelContainer.anyRouter(inMemory: $0 == nil, storeURL: $0) },
        now: Date = Date()
    ) throws -> Outcome {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            return Outcome(container: try make(url), note: nil)
        } catch {
            let kept = moveAside(url, now: now)
            let keptText = kept.map { " Your old chats were kept as \($0)." } ?? ""
            do {
                return Outcome(container: try make(url), note: "Your chats could not be opened, so AnyRouter started a new chat history.\(keptText)")
            } catch {
                return Outcome(container: try make(nil), note: "Your chats could not be opened or saved on this device. This session starts empty and will not be kept.\(keptText)")
            }
        }
    }

    /// Renames the store and its sidecar files to `<name>.unreadable-<time>`. Returns the new name, or nil when nothing was moved.
    static func moveAside(_ url: URL, now: Date) -> String? {
        let fm = FileManager.default
        let stamp = Int(now.timeIntervalSince1970)
        var keptName: String?
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            let name = url.lastPathComponent + ".unreadable-\(stamp)" + suffix
            let target = url.deletingLastPathComponent().appending(path: name)
            if (try? fm.moveItem(at: source, to: target)) != nil, suffix.isEmpty { keptName = name }
        }
        return keptName
    }

    /// The note from this launch, shown once by the root view.
    @MainActor private static var pendingNote: String?
    @MainActor static func post(note: String?) { pendingNote = note }
    @MainActor static func takeNote() -> String? {
        defer { pendingNote = nil }
        return pendingNote
    }
}
