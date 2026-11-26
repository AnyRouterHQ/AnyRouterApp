import SwiftUI

/// One model's page: what it is, what it needs, and every action (download, pause, delete, set as default).
struct ModelDetailView: View {
    let entry: LocalModelEntry

    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    @State private var confirmsDownload = false
    @State private var confirmsDelete = false

    private var hub: any ModelHubService { app.hub }
    private var state: DownloadState { hub.downloadState(for: entry.id) }
    private var device: String { DeviceName.current }
    private var installedDescriptor: ModelDescriptor? {
        models.models.first { $0.id == entry.id && $0.isInstalled }
    }
    private var isLoaded: Bool { app.memory.loadedModelID == entry.id }
    private var downloadWarning: String? {
        FitText.downloadWarning(entry.fitDetail, sizeText: HubLogic.sizeText(entry.descriptor.sizeBytes), device: device)
    }

    var body: some View {
        List {
            Section {
                ModelLabel(model: entry.descriptor)
                Text(entry.summary)
                if let status = HubListOptions.fitStatus(entry, device: device) {
                    Label(status, systemImage: statusSymbol).foregroundStyle(ModelStatusColor.fit(entry))
                }
                if let detail = entry.fitDetail, let text = FitText.explanation(detail, device: device) {
                    Text(text).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Details") {
                LabeledContent("Engine", value: HubListOptions.engineName(entry.descriptor.source))
                if let size = HubLogic.sizeText(entry.descriptor.sizeBytes) { LabeledContent("Download size", value: size) }
                if let detail = entry.fitDetail {
                    LabeledContent("Memory", value: FitText.needs(detail) + (detail.isEstimate ? " (estimate)" : ""))
                }
                if let context = entry.descriptor.contextLength {
                    LabeledContent("Context", value: context.formatted(.number.grouping(.automatic)) + " tokens")
                }
                if !entry.tags.isEmpty { LabeledContent("Tags", value: entry.tags.joined(separator: ", ")) }
                if isLoaded {
                    LabeledContent("In memory", value: FitText.memoryLine(
                        footprintBytes: app.memory.readout.footprintBytes, availableBytes: app.memory.readout.availableBytes))
                }
            }
            Section { actions }
        }
        .navigationTitle(entry.descriptor.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Download anyway?", isPresented: $confirmsDownload, titleVisibility: .visible) {
            Button("Download anyway", role: .destructive) { hub.download(entry) }
        } message: {
            Text(downloadWarning ?? "")
        }
        .confirmationDialog("Delete \(entry.descriptor.displayName)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await hub.delete(modelID: entry.id) } }
        } message: {
            Text("The files are removed from this \(device). You can download it again later.")
        }
        .task { await app.memory.refresh() }
    }

    private var statusSymbol: String {
        if entry.unavailableReason != nil { return "exclamationmark.circle" }
        switch entry.fit {
        case .fits: return "checkmark.circle"
        case .tight: return "exclamationmark.triangle"
        case .wontFit: return "xmark.octagon"
        case .unknown: return "questionmark.circle"
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .notInstalled where entry.unavailableReason != nil:
            Text(entry.unavailableReason ?? "").foregroundStyle(.secondary)
        case .notInstalled, .failed:
            if case .failed(let message) = state { Text(message).foregroundStyle(.red) }
            Button("Download", systemImage: "arrow.down.circle") {
                if downloadWarning != nil { confirmsDownload = true } else { hub.download(entry) }
            }
        case .downloading(let progress):
            LabeledContent("Downloading", value: HubLogic.percent(progress))
            Button("Pause", systemImage: "pause.circle") { hub.pause(modelID: entry.id) }
            Button("Cancel download", systemImage: "xmark.circle", role: .destructive) { hub.cancel(modelID: entry.id) }
        case .paused(let progress):
            LabeledContent("Paused", value: HubLogic.percent(progress))
            Button("Resume", systemImage: "play.circle") { hub.resume(modelID: entry.id) }
            Button("Cancel download", systemImage: "xmark.circle", role: .destructive) { hub.cancel(modelID: entry.id) }
        case .verifying:
            Label("Verifying", systemImage: "checkmark.shield").foregroundStyle(.secondary)
        case .installed:
            if let installedDescriptor {
                Button("Set as Default", systemImage: "star") { models.select(installedDescriptor) }
            }
            if isLoaded {
                Button("Unload from memory", systemImage: "memorychip") { Task { await app.memory.unload() } }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { confirmsDelete = true }
        }
    }
}
