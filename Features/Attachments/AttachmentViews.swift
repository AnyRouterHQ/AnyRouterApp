import PhotosUI
import QuickLook
import SwiftUI
import UIKit

/// Chips above the composer field: a thumbnail for photos, an icon and name for files, each with a remove button.
struct PendingAttachments: View {
    let attachments: [ChatAttachment]
    let ingesting: Int
    var failed: Set<UUID> = []
    let store: AttachmentStore
    var onRemove: (ChatAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentChip(attachment: attachment, store: store, failed: failed.contains(attachment.id)) {
                        onRemove(attachment)
                    }
                }
                if ingesting > 0 { ProgressView().frame(width: 44, height: 44) }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("composer.attachments")
    }
}

/// One pending attachment. The remove button is a full 44 point target.
struct AttachmentChip: View {
    let attachment: ChatAttachment
    let store: AttachmentStore
    /// The file could not be sent. The chip says so and the user can remove it.
    var failed = false
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(.leading, 12)
                    .accessibilityLabel("Could not send")
            }
            if attachment.kind == .image {
                AttachmentThumbnail(attachment: attachment, store: store, side: 44)
                    .clipShape(.rect(cornerRadius: 8))
                    .padding(.leading, 6)
            } else {
                Label(attachment.filename, systemImage: AttachmentLogic.systemImage(for: attachment.kind))
                    .font(.footnote)
                    .lineLimit(1)
                    .frame(maxWidth: 180)
                    .padding(.leading, 12)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Remove \(attachment.filename)")
        }
        .frame(minHeight: 44)
        .background(.quaternary, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("attachment-chip.\(attachment.filename)")
    }
}

/// UIImage is immutable once made; this carries it back from the background task.
private struct SendableImage: @unchecked Sendable { let image: UIImage? }

/// A square preview of a stored photo, read off the main thread.
struct AttachmentThumbnail: View {
    let attachment: ChatAttachment
    let store: AttachmentStore
    let side: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .task(id: attachment.id) {
            let url = attachment.url(in: store.root)
            let pixels = Int(side * 3)
            image = await Task.detached { SendableImage(image: ImageProcessing.thumbnail(at: url, maxSide: pixels)) }.value.image
        }
    }
}

/// Attachments inside the user's bubble: photo thumbnails and file rows. A tap opens a Quick Look preview.
struct MessageAttachments: View {
    let attachments: [ChatAttachment]
    var store: AttachmentStore = .shared
    @State private var preview: URL?

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(attachments) { attachment in
                Button { preview = attachment.url(in: store.root) } label: { content(attachment) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(attachment.kind == .image ? "Photo \(attachment.filename)" : attachment.filename)
                    .accessibilityHint("Opens a preview")
            }
        }
        .quickLookPreview($preview)
    }

    @ViewBuilder
    private func content(_ attachment: ChatAttachment) -> some View {
        if attachment.kind == .image {
            AttachmentThumbnail(attachment: attachment, store: store, side: 160)
                .clipShape(.rect(cornerRadius: 16))
        } else {
            HStack(spacing: 10) {
                Image(systemName: AttachmentLogic.systemImage(for: attachment.kind)).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename).font(.subheadline).lineLimit(1)
                    Text(AttachmentLogic.sizeText(attachment.byteCount)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: 260, alignment: .leading)
            .background(.quaternary, in: .rect(cornerRadius: 14))
        }
    }
}

/// The system camera. Only offered when the device has one.
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
