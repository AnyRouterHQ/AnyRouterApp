import SwiftUI

/// A site's icon in a circle. The icon comes from the site itself (`/favicon.ico`); until it arrives, or when the site
/// has none, the circle shows the first letter of the host.
struct FaviconView: View {
    let source: ReplyFooter.Source
    var size: CGFloat
    @State private var loaded: UIImage?

    var body: some View {
        Group {
            if let image = loaded ?? FaviconCache.shared.cached(source.faviconURL) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Text(source.host.prefix(1).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        // Demo data never touches the network, so the screenshots always show the letter.
        .task(id: source.faviconURL) {
            guard !DemoData.isEnabled else { return }
            loaded = await FaviconCache.shared.image(for: source.faviconURL)
        }
        .frame(width: size, height: size)
        .background(Color(.secondarySystemFill))
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// Up to three favicons that overlap, each with a thin ring in the page color so the circles stay apart.
struct FaviconChain: View {
    let sources: [ReplyFooter.Source]
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 18

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                FaviconView(source: source, size: size)
                    .overlay { Circle().stroke(Color(.systemBackground), lineWidth: 1.5) }
                    .zIndex(Double(sources.count - index))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The list behind "N sources": title and host of each page; a tap opens it in Safari.
struct SourcesSheet: View {
    let sources: [ReplyFooter.Source]
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 28

    var body: some View {
        NavigationStack {
            List(sources) { source in
                Link(destination: source.url) {
                    HStack(spacing: 12) {
                        FaviconView(source: source, size: iconSize)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title).font(.body).lineLimit(2)
                            Text(source.host).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens in Safari")
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
