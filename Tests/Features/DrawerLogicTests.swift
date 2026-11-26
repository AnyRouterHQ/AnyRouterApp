import CoreGraphics
import Testing
@testable import AnyRouter

struct DrawerLogicTests {
    @Test func widthLeavesA64ptPeekAndCapsAt360() {
        #expect(DrawerLogic.width(forScreen: 390) == 326)
        #expect(DrawerLogic.width(forScreen: 600) == 360)
        #expect(DrawerLogic.width(forScreen: 40) == 0)
    }

    @Test func progressFollowsTheFingerAndClamps() {
        #expect(DrawerLogic.progress(isOpen: false, drag: 100, width: 200) == 0.5)
        #expect(DrawerLogic.progress(isOpen: false, drag: 500, width: 200) == 1)
        #expect(DrawerLogic.progress(isOpen: false, drag: -50, width: 200) == 0)
        #expect(DrawerLogic.progress(isOpen: true, drag: -100, width: 200) == 0.5)
        #expect(DrawerLogic.progress(isOpen: true, drag: 80, width: 200) == 1)
        #expect(DrawerLogic.progress(isOpen: true, drag: 0, width: 0) == 0)
    }

    @Test func closedDrawerOnlyTracksHorizontalDragsFromTheLeftEdge() {
        let right = CGSize(width: 30, height: 4)
        #expect(DrawerLogic.tracks(startX: 5, translation: right, isOpen: false, width: 300))
        #expect(!DrawerLogic.tracks(startX: 80, translation: right, isOpen: false, width: 300))
        #expect(!DrawerLogic.tracks(startX: 5, translation: CGSize(width: 4, height: 30), isOpen: false, width: 300))
    }

    @Test func openDrawerTracksFromItsRightEdgeAndTheChatOnly() {
        let left = CGSize(width: -30, height: 2)
        #expect(DrawerLogic.tracks(startX: 400, translation: left, isOpen: true, width: 300))
        #expect(DrawerLogic.tracks(startX: 290, translation: left, isOpen: true, width: 300))
        // Inside the list the row swipe actions own horizontal drags.
        #expect(!DrawerLogic.tracks(startX: 100, translation: left, isOpen: true, width: 300))
    }

    @Test func settlesOpenPastHalfwayOrOnAFling() {
        #expect(DrawerLogic.shouldOpen(isOpen: false, predictedEnd: 200, width: 300))
        #expect(!DrawerLogic.shouldOpen(isOpen: false, predictedEnd: 100, width: 300))
        #expect(!DrawerLogic.shouldOpen(isOpen: false, predictedEnd: 150, width: 300))
    }

    @Test func settlesClosedPastHalfwayOrOnAFling() {
        #expect(!DrawerLogic.shouldOpen(isOpen: true, predictedEnd: -200, width: 300))
        #expect(DrawerLogic.shouldOpen(isOpen: true, predictedEnd: -100, width: 300))
        #expect(DrawerLogic.shouldOpen(isOpen: true, predictedEnd: 0, width: 300))
    }
}
