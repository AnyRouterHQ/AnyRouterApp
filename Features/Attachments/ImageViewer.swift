import SwiftUI
import UIKit

/// A photo of a message on the whole screen: pinch or double-tap to zoom, drag to move it when zoomed, pull it down or
/// up to close it, and share it from the corner.
struct ImageViewer: View {
    let attachment: ChatAttachment
    let store: AttachmentStore
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var pull: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).opacity(ImageZoom.backdropOpacity(pull: pull)).ignoresSafeArea()
                if let image {
                    ZoomableImage(image: image, onPull: { pull = $0 }, onDismiss: { dismiss() })
                        .ignoresSafeArea()
                        .accessibilityLabel(attachment.filename)
                        .accessibilityAddTraits(.isImage)
                        .accessibilityIdentifier("image-viewer.image")
                } else {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .primaryAction) { ShareLink(item: attachment.url(in: store.root)) }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(.clear)
        .accessibilityIdentifier("image-viewer")
        .task(id: attachment.id) {
            let url = attachment.url(in: store.root)
            image = await Task.detached { ViewerImage(image: ImageProcessing.thumbnail(at: url, maxSide: 4096)) }.value.image
        }
    }
}

/// UIImage is immutable once made; this carries it back from the background task.
private struct ViewerImage: @unchecked Sendable { let image: UIImage? }

/// Pinch zoom with the system's own scroll view: it does the pinch, the pan while zoomed and the bounce correctly, which a
/// SwiftUI gesture stack does not without a lot of code. A pull past the edge at normal size closes the viewer.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    var onPull: (CGFloat) -> Void
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPull: onPull, onDismiss: onDismiss) }

    func makeUIView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView()
        scroll.imageView.image = image
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = ImageZoom.minimumScale
        scroll.maximumZoomScale = ImageZoom.maximumScale
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        scroll.contentInsetAdjustmentBehavior = .never
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        context.coordinator.imageView = scroll.imageView
        return scroll
    }

    func updateUIView(_ scroll: ZoomScrollView, context: Context) {
        context.coordinator.onPull = onPull
        context.coordinator.onDismiss = onDismiss
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onPull: (CGFloat) -> Void
        var onDismiss: () -> Void
        weak var imageView: UIImageView?

        init(onPull: @escaping (CGFloat) -> Void, onDismiss: @escaping () -> Void) {
            self.onPull = onPull
            self.onDismiss = onDismiss
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onPull(scrollView.zoomScale <= ImageZoom.minimumScale + 0.01 ? scrollView.contentOffset.y : 0)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if ImageZoom.shouldDismiss(pull: scrollView.contentOffset.y, scale: scrollView.zoomScale) { onDismiss() }
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView, let imageView else { return }
            let target = ImageZoom.doubleTapTarget(current: scroll.zoomScale)
            if target == ImageZoom.minimumScale {
                scroll.setZoomScale(target, animated: true)
            } else {
                let rect = ImageZoom.zoomRect(center: gesture.location(in: imageView), scale: target, size: scroll.bounds.size)
                scroll.zoom(to: rect, animated: true)
            }
        }
    }
}

/// A scroll view whose one subview is the photo, fitted to the screen whenever it is not zoomed.
final class ZoomScrollView: UIScrollView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == ImageZoom.minimumScale {
            // Not `bounds`: its origin moves with the offset while the photo is pulled.
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }
}
