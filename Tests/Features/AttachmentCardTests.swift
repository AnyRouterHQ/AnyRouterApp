import CoreGraphics
import Foundation
import Testing
@testable import AnyRouter

struct AttachmentCardTests {
    private func attachment(_ kind: ChatAttachment.Kind, _ name: String, bytes: Int64 = 16_000) -> ChatAttachment {
        ChatAttachment(id: UUID(), kind: kind, filename: name, utType: "public.data", byteCount: bytes, relativePath: "t/\(name)")
    }

    @Test func theLineUnderAFileNamesItsKindTypeAndSize() {
        let size = AttachmentLogic.sizeText(16_000)
        #expect(AttachmentLogic.subtitle(for: attachment(.pdf, "Contract.pdf")) == "Document · PDF · \(size)")
        #expect(AttachmentLogic.subtitle(for: attachment(.text, "notes.md")) == "Text · MD · \(size)")
        #expect(AttachmentLogic.subtitle(for: attachment(.image, "photo.heic")) == "Photo · HEIC · \(size)")
        #expect(AttachmentLogic.subtitle(for: attachment(.audio, "memo.m4a")) == "Audio · M4A · \(size)")
    }

    @Test func aFileWithoutAnExtensionLeavesOutTheType() {
        let size = AttachmentLogic.sizeText(16_000)
        #expect(AttachmentLogic.subtitle(for: attachment(.text, "README")) == "Text · \(size)")
    }
}

struct ImageZoomTests {
    @Test func aDoubleTapZoomsInAndTheNextOneBackOut() {
        #expect(ImageZoom.doubleTapTarget(current: 1) == ImageZoom.doubleTapScale)
        #expect(ImageZoom.doubleTapTarget(current: 1.005) == ImageZoom.doubleTapScale, "a hair above the minimum counts as not zoomed")
        #expect(ImageZoom.doubleTapTarget(current: 2.5) == ImageZoom.minimumScale)
        #expect(ImageZoom.doubleTapTarget(current: 4) == ImageZoom.minimumScale)
    }

    @Test func theZoomRectIsCenteredOnTheTapAndSmallerByTheScale() {
        let rect = ImageZoom.zoomRect(center: CGPoint(x: 200, y: 400), scale: 2, size: CGSize(width: 400, height: 800))
        #expect(rect == CGRect(x: 100, y: 200, width: 200, height: 400))
    }

    @Test func onlyAPhotoAtNormalSizeIsDismissedByAFarEnoughPull() {
        #expect(ImageZoom.shouldDismiss(pull: 120, scale: 1))
        #expect(ImageZoom.shouldDismiss(pull: -120, scale: 1))
        #expect(!ImageZoom.shouldDismiss(pull: 40, scale: 1), "too short")
        #expect(!ImageZoom.shouldDismiss(pull: 300, scale: 2), "zoomed in: the pull moves the photo")
    }

    @Test func theBackdropFadesWithThePullButNeverGoesAway() {
        #expect(ImageZoom.backdropOpacity(pull: 0) == 1)
        #expect(ImageZoom.backdropOpacity(pull: 100) == 0.75)
        #expect(ImageZoom.backdropOpacity(pull: -100) == 0.75)
        #expect(ImageZoom.backdropOpacity(pull: 900) == 0.3)
    }
}
