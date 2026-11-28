import SwiftUI

/// The question every list of local models can ask before it acts: delete this one. A download never asks: the fit
/// estimate is a guess, and the row already says when a model may not load.
@MainActor @Observable
final class LocalModelPrompts {
    var pendingDelete: LocalModelEntry?
}

/// Swipe actions and context menu shared by Local Models and Browse models.
@MainActor
struct LocalModelActions {
    let hub: any ModelHubService
    let models: ModelStore
    let memory: MemoryMonitor
    let prompts: LocalModelPrompts
    /// "iPhone" or "iPad".
    let device: String

    @ViewBuilder
    func swipe(_ entry: LocalModelEntry, state: DownloadState) -> some View {
        switch state {
        case .installed:
            Button("Delete", systemImage: "trash", role: .destructive) { prompts.pendingDelete = entry }
        case .downloading:
            Button("Cancel", systemImage: "xmark", role: .destructive) { hub.cancel(modelID: entry.id) }
            Button("Pause", systemImage: "pause") { hub.pause(modelID: entry.id) }.tint(ARPalette.tint)
        case .paused:
            Button("Cancel", systemImage: "xmark", role: .destructive) { hub.cancel(modelID: entry.id) }
            Button("Resume", systemImage: "play") { hub.resume(modelID: entry.id) }.tint(ARPalette.tint)
        case .notInstalled, .failed:
            if entry.unavailableReason == nil {
                Button("Download", systemImage: "arrow.down") { hub.download(entry) }.tint(ARPalette.tint)
            }
        case .verifying:
            EmptyView()
        }
    }

    @ViewBuilder
    func menu(_ entry: LocalModelEntry, state: DownloadState) -> some View {
        switch state {
        case .installed:
            if let descriptor = models.models.first(where: { $0.id == entry.id && $0.isInstalled }) {
                Button("Set as Default", systemImage: "star") { models.select(descriptor) }
            }
            if memory.loadedModelID == entry.id {
                Button("Unload", systemImage: "memorychip") { Task { await memory.unload() } }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { prompts.pendingDelete = entry }
        case .downloading:
            Button("Pause", systemImage: "pause") { hub.pause(modelID: entry.id) }
            Button("Cancel download", systemImage: "xmark", role: .destructive) { hub.cancel(modelID: entry.id) }
        case .paused:
            Button("Resume", systemImage: "play") { hub.resume(modelID: entry.id) }
            Button("Cancel download", systemImage: "xmark", role: .destructive) { hub.cancel(modelID: entry.id) }
        case .notInstalled, .failed:
            if entry.unavailableReason == nil {
                Button("Download", systemImage: "arrow.down.circle") { hub.download(entry) }
            }
        case .verifying:
            EmptyView()
        }
    }
}

/// The confirmation dialogs behind `LocalModelPrompts`.
struct LocalModelDialogs: ViewModifier {
    let prompts: LocalModelPrompts
    let hub: any ModelHubService
    let device: String

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete model?",
                isPresented: Binding(get: { prompts.pendingDelete != nil }, set: { if !$0 { prompts.pendingDelete = nil } }),
                titleVisibility: .visible, presenting: prompts.pendingDelete
            ) { entry in
                Button("Delete \(entry.descriptor.displayName)", role: .destructive) {
                    Task { await hub.delete(modelID: entry.id) }
                }
            } message: { _ in
                Text("The files are removed from this \(device). You can download it again later.")
            }    }
}
