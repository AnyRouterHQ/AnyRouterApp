import CoreGraphics
import Foundation
import Testing
@testable import AnyRouter

struct KeyboardZonesTests {
    @Test func pointsInsideAZoneAreKept() {
        var zones = KeyboardZones()
        zones.set(CGRect(x: 0, y: 700, width: 390, height: 100), for: UUID())
        #expect(zones.contains(CGPoint(x: 10, y: 750)))
        #expect(zones.contains(CGPoint(x: 0, y: 700)))
        #expect(!zones.contains(CGPoint(x: 10, y: 699)))
        #expect(!zones.contains(CGPoint(x: 391, y: 750)))
    }

    @Test func eachZoneIsTrackedAndRemovedByItsOwnID() {
        var zones = KeyboardZones()
        let a = UUID(), b = UUID()
        zones.set(CGRect(x: 0, y: 0, width: 50, height: 50), for: a)
        zones.set(CGRect(x: 100, y: 100, width: 50, height: 50), for: b)
        #expect(zones.contains(CGPoint(x: 25, y: 25)) && zones.contains(CGPoint(x: 125, y: 125)))
        zones.remove(a)
        #expect(!zones.contains(CGPoint(x: 25, y: 25)))
        #expect(zones.contains(CGPoint(x: 125, y: 125)))
    }

    @Test func movingAZoneReplacesItsOldFrame() {
        var zones = KeyboardZones()
        let id = UUID()
        zones.set(CGRect(x: 0, y: 0, width: 50, height: 50), for: id)
        zones.set(CGRect(x: 200, y: 200, width: 50, height: 50), for: id)
        #expect(!zones.contains(CGPoint(x: 25, y: 25)))
        #expect(zones.contains(CGPoint(x: 225, y: 225)))
    }

    @Test func noZonesKeepsNothing() {
        #expect(!KeyboardZones().contains(.zero))
    }
}
