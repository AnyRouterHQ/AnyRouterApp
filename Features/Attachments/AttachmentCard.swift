import QuickLookThumbnailing
import SwiftUI

/// A file in a message: its first-page thumbnail or a symbol, the name, and "Document · PDF · 16 KB" under it.
struct AttachmentCard: View {
    let attachment: ChatAttachment
    let store: AttachmentStore
    @ScaledMetric(relativeTo: .body) private var thumbnailSide: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnail(attachment: attachment, store: store, side: thumbnailSide)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename).font(.subheadline).lineLimit(1)
                Text(AttachmentLogic.subtitle(for: attachment)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: 300, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
    }
}

/// A square thumbnail of a stored file made by the system (a PDF's first page, the start of a text file). Until it is
/// ready, and for a file the system cannot draw, the symbol of its kind.
struct FileThumbnail: View {
    let attachment: ChatAttachment
    let store: AttachmentStore
    let side: CGFloat
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: AttachmentLogic.systemImage(for: attachment.kind))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: 8))
        .task(id: attachment.id) {
            image = await ThumbnailMaker.image(for: attachment.url(in: store.root), side: side, scale: displayScale)
        }
    }
}

/// UIImage is immutable once made; this carries it out of the system's callback.
private struct ThumbnailBox: @unchecked Sendable { let image: UIImage? }

/// QLThumbnailGenerator behind one async call.
enum ThumbnailMaker {
    static func image(for url: URL, side: CGFloat, scale: CGFloat) async -> UIImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .thumbnail)
        let box = await withCheckedContinuation { (continuation: CheckedContinuation<ThumbnailBox, Never>) in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: ThumbnailBox(image: representation?.uiImage))
            }
        }
        return box.image
    }
}
