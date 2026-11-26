import MarkdownUI
import SwiftUI

/// Remote images in a reply are never fetched. A model, or text it read from a page or a file, could put part of the
/// conversation in an image URL, and the request would leave the device without a tap.
struct BlockedImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        Label("Image not loaded", systemImage: "photo")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// The same rule for images inside a line of text.
struct BlockedInlineImageProvider: InlineImageProvider {
    struct Blocked: Error {}

    func image(with url: URL, label: String) async throws -> Image {
        throw Blocked()
    }
}
