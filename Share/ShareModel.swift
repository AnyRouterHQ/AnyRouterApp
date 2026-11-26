import Foundation
import Observation
import UniformTypeIdentifiers

/// Reads what the host app shared, then saves it for AnyRouter.
@MainActor @Observable
final class ShareModel {
    enum Stage: Equatable {
        case loading
        case ready
        case saved
        case failed(String)
    }

    private(set) var stage = Stage.loading
    var action = ShareAction.ask
    private(set) var text: String?
    private(set) var link: URL?
    private(set) var files: [(file: SharedFile, url: URL)] = []

    private let providers: [NSItemProvider]
    private let inbox: ShareInbox?

    init(providers: [NSItemProvider], inbox: ShareInbox?) {
        self.providers = providers
        self.inbox = inbox
        Task { await load() }
    }

    var hasText: Bool { joinedText != nil }
    var hasFiles: Bool { !files.isEmpty }

    /// Presets apply to text, links and PDFs. A photo goes to the "Read text" sheet in the app.
    var offersActions: Bool { hasText || files.contains { $0.file.kind == .pdf } }

    /// The text and the link, one under the other.
    var joinedText: String? {
        let parts = [text, link?.absoluteString].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    // MARK: Loading

    private func load() async {
        var texts: [String] = []
        for provider in providers {
            if let pdf = await copy(provider, conformingTo: .pdf, kind: .pdf, fallbackName: "Document.pdf") {
                files.append(pdf)
            } else if let image = await copy(provider, conformingTo: .image, kind: .image, fallbackName: "Photo.jpg") {
                files.append(image)
            } else if let url = await loadURL(provider) {
                link = url
            } else if let shared = await loadText(provider) {
                texts.append(shared)
            }
        }
        text = texts.isEmpty ? nil : texts.joined(separator: "\n\n")
        stage = hasText || hasFiles ? .ready : .failed("AnyRouter can read text, links, images and PDFs.")
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    /// A web link. A `file://` URL is a file, not a link.
    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                let url = item as? URL
                continuation.resume(returning: url?.isFileURL == false ? url : nil)
            }
        }
    }

    /// Copies a file the host app shared into this extension's temporary folder. The system removes its own copy as
    /// soon as the handler returns.
    private func copy(_ provider: NSItemProvider, conformingTo type: UTType, kind: SharedFile.Kind,
                      fallbackName: String) async -> (file: SharedFile, url: URL)? {
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: type) == true })
        else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: identifier) { source, _ in
                guard let source else {
                    continuation.resume(returning: nil)
                    return
                }
                let name = source.lastPathComponent.isEmpty ? fallbackName : source.lastPathComponent
                let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                let destination = folder.appending(path: name)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: source, to: destination)
                    continuation.resume(returning: (SharedFile(filename: name, kind: kind), destination))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: Sending

    /// With an App Group the share is saved in the inbox and the app is asked to open. Without one, a short text
    /// travels in a link. Anything else cannot reach the app, and the message says why.
    func send(opensApp: (URL) -> Void) {
        if let inbox {
            do {
                var payload = SharedPayload(text: text, url: link?.absoluteString, action: action)
                let folder = try inbox.prepare(payload.id)
                for item in files {
                    try FileManager.default.copyItem(at: item.url, to: folder.appending(path: item.file.filename))
                    payload.files.append(item.file)
                }
                try inbox.save(payload)
                stage = .saved
                opensApp(ShareDeepLink.shareURL)
            } catch {
                stage = .failed(ShareMessages.saveFailed)
            }
        } else if files.isEmpty, let body = joinedText, let url = ShareDeepLink.askURL(text: body, action: action) {
            stage = .saved
            opensApp(url)
        } else {
            stage = .failed(ShareMessages.noAppGroup(hasFiles: hasFiles))
        }
    }
}
