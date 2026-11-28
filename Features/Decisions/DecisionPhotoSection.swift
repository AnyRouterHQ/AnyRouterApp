import PhotosUI
import SwiftUI
import UIKit

/// The photo row of a decision: thumbnails with remove buttons, and one Add menu for Photos, Files and the live camera.
struct DecisionPhotoSection: View {
    let store: DecisionsStore
    @State private var picked: [PhotosPickerItem] = []
    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var showsCamera = false

    var body: some View {
        Section {
            if !store.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(store.images.enumerated()), id: \.offset) { index, image in
                            DecisionThumbnail(data: image.data) { store.removeImage(at: index) }
                        }
                    }
                }
            }
            if store.showsImageInput {
                Menu {
                    if store.app?.photoFirst == true { cameraButton }
                    Button("Photos", systemImage: "photo") { showsPhotos = true }
                    Button("Files", systemImage: "folder") { showsFiles = true }
                    if store.app?.photoFirst != true { cameraButton }
                } label: {
                    Label("Add photo", systemImage: "photo.badge.plus")
                }
                .disabled(store.images.count >= DecisionsLogic.maxImages)
                .accessibilityIdentifier("decisions-add-photo")
                .photosPicker(
                    isPresented: $showsPhotos, selection: $picked,
                    maxSelectionCount: max(1, DecisionsLogic.maxImages - store.images.count), matching: .images)
                .onChange(of: picked) { _, items in
                    guard !items.isEmpty else { return }
                    picked = []
                    Task {
                        var sources: [Data] = []
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self) { sources.append(data) }
                        }
                        await store.addImages(sources)
                    }
                }
                .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                    guard case .success(let urls) = result else { return }
                    Task { await store.addImages(await Self.read(urls)) }
                }

                if showsCamera {
                    DecisionCameraPanel { data in Task { await store.addImages([data]) } } onClose: { showsCamera = false }
                }
            }
        } footer: {
            if let error = store.imageError {
                Text(error)
            } else if store.selectedModel?.acceptsImages == false {
                Text("This model can't read photos. Choose another model.")
            }
        }
    }

    private var cameraButton: some View {
        Button("Camera", systemImage: "camera") { showsCamera = true }
            .disabled(!CameraPicker.isAvailable)
    }

    /// The bytes of each picked file that is not huge. The URLs are security scoped.
    @concurrent private static func read(_ urls: [URL]) async -> [Data] {
        urls.compactMap { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, Int64(size) > AttachmentLogic.maxFileBytes {
                return nil
            }
            return try? Data(contentsOf: url)
        }
    }
}

/// A small preview of one photo with its remove button.
private struct DecisionThumbnail: View {
    let data: Data
    let remove: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Label("Remove photo", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
        }
        .task(id: data) {
            image = await UIImage(data: data)?.byPreparingThumbnail(ofSize: CGSize(width: 176, height: 176))
        }
    }
}
