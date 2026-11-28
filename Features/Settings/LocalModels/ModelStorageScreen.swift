import SwiftUI

/// Settings › Local Models › Storage: everything in the models and voice folders, biggest first, whatever the catalog says.
/// Swipe a row to delete it. A stock inset-grouped list.
struct ModelStorageScreen: View {
    @Environment(AppState.self) private var app

    @State private var freeBytes: Int64?
    @State private var confirmsDeleteAll = false

    private var hub: any ModelHubService { app.hub }
    private var device: String { DeviceName.current }
    private var items: [StorageInventoryLogic.Item] { hub.storageItems }
    private var voiceItems: [StorageInventoryLogic.Item] { app.voice.storageItems }
    private var unfinished: [StorageInventoryLogic.Item] { StorageInventoryLogic.unfinished(items + voiceItems) }
    private var installed: [LocalModelEntry] {
        LocalModelsLogic.installed(hub.catalog + hub.offCatalogModels, state: { hub.downloadState(for: $0) })
    }
    private var storage: LocalModelsLogic.Storage { LocalModelsLogic.storage(installed: installed, freeBytes: freeBytes) }

    var body: some View {
        List {
            Section {
                LabeledContent("Models", value: FitFormat.gigabytes(StorageInventoryLogic.totalBytes(items + voiceItems)))
                if let freeBytes {
                    LabeledContent("Free on device", value: FitFormat.gigabytes(freeBytes))
                }
            }
            if items.isEmpty && voiceItems.isEmpty {
                ContentUnavailableView("No Models Stored", systemImage: "internaldrive",
                                       description: Text("Downloaded models show here with their size."))
            } else {
                if !items.isEmpty {
                    Section("On This \(device)") {
                        ForEach(items) { row($0, voice: false) }
                    }
                }
                if !voiceItems.isEmpty {
                    Section("Voice") {
                        ForEach(voiceItems) { row($0, voice: true) }
                    }
                }
            }
            Section {
                LabeledContent("Unfinished downloads", value: FitFormat.gigabytes(StorageInventoryLogic.totalBytes(unfinished)))
                Button("Delete Unfinished Downloads", role: .destructive) {
                    Task {
                        await hub.deleteUnfinishedDownloads()
                        for item in StorageInventoryLogic.unfinished(voiceItems) { await app.voice.deleteStorageItem(item) }
                    }
                }
                .disabled(unfinished.isEmpty)
                .accessibilityIdentifier("storage.deleteUnfinished")
            } footer: {
                Text("Downloads that stopped part way. A download that is running now is kept.")
            }
            Section {
                Button("Delete All Models", role: .destructive) { confirmsDeleteAll = true }
                    .disabled(installed.isEmpty)
                    .accessibilityIdentifier("local.deleteAll")
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("storage.list")
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await hub.reload()
            await app.voice.rescanStorage()
        }
        .confirmationDialog("Delete all models?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
            Button("Delete All Models", role: .destructive) { Task { await hub.deleteAllModels() } }
        } message: {
            Text(LocalModelsLogic.deleteAllMessage(storage, device: device))
        }
        .task {
            freeBytes = HubScreen.freeDiskBytes()
            await app.voice.rescanStorage()
        }
    }

    /// `voice`: the row is in the voice folder, so the voice hub deletes it.
    private func row(_ item: StorageInventoryLogic.Item, voice: Bool) -> some View {
        LabeledContent {
            Text(FitFormat.gigabytes(item.bytes))
        } label: {
            Text(item.name)
            if let note = StorageInventoryLogic.note(item) { Text(note) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("storage.row.\(item.folders[0])")
        .swipeActions(edge: .trailing) {
            if !item.isRunning {
                Button("Delete", role: .destructive) {
                    Task {
                        if voice { await app.voice.deleteStorageItem(item) } else { await hub.deleteStorageItem(item) }
                    }
                }
            }
        }
    }
}
