import Foundation
import Testing
@testable import AnyRouter

/// The words and actions of the photo support row on a model's page, and when a model counts as reading photos.
struct PhotoSupportLogicTests {
    private let size: Int64 = 345_911_008

    @Test func theActionNamesTheDownloadSize() {
        #expect(PhotoSupportLogic.addTitle(sizeBytes: size) == "Add photo support · 346 MB")
        #expect(PhotoSupportLogic.addTitle(sizeBytes: nil) == "Add photo support")
        #expect(PhotoSupportLogic.removeTitle == "Remove photo support")
    }

    @Test func notInstalledOffersOneActionAndAFailureKeepsItsMessage() {
        let add = PhotoSupportRow.Action.add(title: "Add photo support · 346 MB")
        #expect(PhotoSupportLogic.row(state: .notInstalled, sizeBytes: size) == PhotoSupportRow(actions: [add]))
        let failed = PhotoSupportLogic.row(state: .failed("No space"), sizeBytes: size)
        #expect(failed == PhotoSupportRow(failure: "No space", actions: [add]), "a failed download can be tried again")
        #expect(add.title == "Add photo support · 346 MB")
    }

    @Test func aDownloadShowsItsProgressAndCanBeCancelledOrResumed() {
        let running = PhotoSupportLogic.row(state: .downloading(progress: 0.5), sizeBytes: size)
        #expect(running == PhotoSupportRow(status: .init(label: "Adding photo support", value: "50%"), actions: [.cancel]))
        let unknown = PhotoSupportLogic.row(state: .downloading(progress: nil), sizeBytes: size)
        #expect(unknown.status?.value == "…")
        let paused = PhotoSupportLogic.row(state: .paused(progress: 0.25), sizeBytes: size)
        #expect(paused == PhotoSupportRow(status: .init(label: "Photo support paused", value: "25%"), actions: [.resume, .cancel]))
        #expect(PhotoSupportRow.Action.resume.title == "Resume")
        #expect(PhotoSupportRow.Action.cancel.title == "Cancel download")
    }

    @Test func verifyingHasNoActionAndAnInstalledAddOnOffersRemove() {
        let verifying = PhotoSupportLogic.row(state: .verifying, sizeBytes: size)
        #expect(verifying == PhotoSupportRow(status: .init(label: "Verifying photo support", value: nil), actions: []))
        let installed = PhotoSupportLogic.row(state: .installed, sizeBytes: size)
        #expect(installed == PhotoSupportRow(actions: [.remove]))
        #expect(PhotoSupportRow.Action.remove.title == "Remove photo support")
    }

    @Test func aModelReadsPhotosOnlyWithRoomAndAnInstalledOptionalProjector() {
        #expect(PhotoSupportLogic.readsPhotos(roomForProjector: true, addOnInstalled: nil), "the projector came with the model")
        #expect(PhotoSupportLogic.readsPhotos(roomForProjector: true, addOnInstalled: true))
        #expect(!PhotoSupportLogic.readsPhotos(roomForProjector: true, addOnInstalled: false), "add-on not downloaded")
        #expect(!PhotoSupportLogic.readsPhotos(roomForProjector: false, addOnInstalled: true), "no room on this device")
        #expect(!PhotoSupportLogic.readsPhotos(roomForProjector: false, addOnInstalled: nil))
    }

    @Test func theVisionCapabilityIsSetOrDroppedAndTheRestStays() {
        #expect(PhotoSupportLogic.capabilities(["chat", "reasoning"], readsPhotos: true) == ["chat", "reasoning", "vision"])
        #expect(PhotoSupportLogic.capabilities(["chat", "vision"], readsPhotos: false) == ["chat"])
        #expect(PhotoSupportLogic.capabilities(["chat"], readsPhotos: false) == ["chat"])
    }
}
