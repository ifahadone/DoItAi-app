import XCTest
import CoreGraphics
@testable import DesignSystem

final class SectographLayoutTests: XCTestCase {
    // 200×200, ring 20 ⇒ center (100,100), outer 100, inner 80.
    private let layout = SectographLayout(size: CGSize(width: 200, height: 200), ringWidth: 20)
    private let halfPi = Double.pi / 2

    func testCardinalAngles() {
        XCTAssertEqual(layout.angle(forMinute: 0), -halfPi, accuracy: 1e-9)      // midnight → top
        XCTAssertEqual(layout.angle(forMinute: 360), 0, accuracy: 1e-9)          // 6am → right
        XCTAssertEqual(layout.angle(forMinute: 720), halfPi, accuracy: 1e-9)     // noon → bottom
        XCTAssertEqual(layout.angle(forMinute: 1080), Double.pi, accuracy: 1e-9) // 6pm → left
    }

    func testAngleMinuteRoundTrips() {
        for minute in stride(from: 0, to: 1440, by: 37) {
            XCTAssertEqual(layout.minute(forAngle: layout.angle(forMinute: minute)), minute,
                           "round-trip failed at \(minute)")
        }
    }

    func testPointForMinute() {
        let top = layout.point(forMinute: 0, radius: 90)
        XCTAssertEqual(top.x, 100, accuracy: 1e-6)
        XCTAssertEqual(top.y, 10, accuracy: 1e-6)   // above center
        let right = layout.point(forMinute: 360, radius: 90)
        XCTAssertEqual(right.x, 190, accuracy: 1e-6)
        XCTAssertEqual(right.y, 100, accuracy: 1e-6)
    }

    func testTimeAtPoint() {
        XCTAssertEqual(layout.time(at: CGPoint(x: 100, y: 10)), 0)    // top
        XCTAssertEqual(layout.time(at: CGPoint(x: 190, y: 100)), 360) // right
        XCTAssertEqual(layout.time(at: CGPoint(x: 100, y: 190)), 720) // bottom
    }

    func testRingContains() {
        XCTAssertTrue(layout.ringContains(layout.point(forMinute: 300, radius: 90)))  // in band
        XCTAssertFalse(layout.ringContains(layout.center))                            // hole
        XCTAssertFalse(layout.ringContains(CGPoint(x: 100, y: -50)))                  // outside
    }

    func testHitTestFindsBlock() {
        let item = SectographItem(id: "morning", startMinute: 600, endMinute: 660) // 10–11am
        let onArc = layout.point(forMinute: 630, radius: 90)
        XCTAssertEqual(layout.hitTest(at: onArc, items: [item]), "morning")
        // Right angle but wrong radius (in the hole) → no hit.
        XCTAssertNil(layout.hitTest(at: layout.point(forMinute: 630, radius: 10), items: [item]))
        // Different time → no hit.
        XCTAssertNil(layout.hitTest(at: layout.point(forMinute: 120, radius: 90), items: [item]))
    }

    func testHitTestWrapsMidnight() {
        let night = SectographItem(id: "night", startMinute: 1380, endMinute: 60) // 11pm–1am
        XCTAssertEqual(layout.hitTest(at: layout.point(forMinute: 1410, radius: 90), items: [night]), "night")
        XCTAssertEqual(layout.hitTest(at: layout.point(forMinute: 30, radius: 90), items: [night]), "night")
        XCTAssertNil(layout.hitTest(at: layout.point(forMinute: 120, radius: 90), items: [night]))
    }

    func testDurationMinutes() {
        XCTAssertEqual(SectographItem(id: "a", startMinute: 600, endMinute: 660).durationMinutes, 60)
        XCTAssertEqual(SectographItem(id: "b", startMinute: 1380, endMinute: 60).durationMinutes, 120) // wraps
    }

    func testArcsResolveAnglesAndRadii() {
        let arcs = layout.arcs(for: [SectographItem(id: "x", startMinute: 0, endMinute: 360, colorHex: "#FF0000")])
        XCTAssertEqual(arcs.count, 1)
        XCTAssertEqual(arcs[0].startAngle, -halfPi, accuracy: 1e-9)
        XCTAssertEqual(arcs[0].endAngle, 0, accuracy: 1e-9)
        XCTAssertEqual(arcs[0].innerRadius, 80, accuracy: 1e-9)
        XCTAssertEqual(arcs[0].outerRadius, 100, accuracy: 1e-9)
        XCTAssertEqual(arcs[0].colorHex, "#FF0000")
    }
}
