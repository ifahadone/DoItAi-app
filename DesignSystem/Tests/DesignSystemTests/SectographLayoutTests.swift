import XCTest
import CoreGraphics
@testable import DesignSystem

final class SectographLayoutTests: XCTestCase {
    // 200×200, ring 20 ⇒ center (100,100), outer 100, inner 80.
    private let layout = SectographLayout(size: CGSize(width: 200, height: 200), ringWidth: 20)
    private let halfPi = Double.pi / 2

    func testClockLabels() {
        XCTAssertEqual(SectographLayout.clockLabel(forHour: 0), "12a")
        XCTAssertEqual(SectographLayout.clockLabel(forHour: 6), "6a")
        XCTAssertEqual(SectographLayout.clockLabel(forHour: 12), "12p")
        XCTAssertEqual(SectographLayout.clockLabel(forHour: 15), "3p")
        XCTAssertEqual(SectographLayout.clockLabel(forHour: 21), "9p")
        XCTAssertEqual(SectographLayout.clockLabel(forHour: 24), "12a") // wraps
    }

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

    // MARK: - Aurora label-placement geometry (P5-5)

    func testMidAngleSimple() {
        let item = SectographItem(id: "am", startMinute: 540, endMinute: 660) // 9–11am, mid = 600
        XCTAssertEqual(layout.midAngle(for: item), layout.angle(forMinute: 600), accuracy: 1e-9)
    }

    func testMidAngleWrapsMidnight() {
        let night = SectographItem(id: "n", startMinute: 1380, endMinute: 60) // 11pm–1am, mid = midnight
        XCTAssertEqual(layout.midAngle(for: night), -halfPi, accuracy: 1e-9) // top of the dial
    }

    func testShouldLabelThreshold() {
        // 15-min arc (~5.9pt centerline) can't carry a 20-char title.
        let tiny = SectographItem(id: "t", startMinute: 600, endMinute: 615)
        XCTAssertFalse(layout.shouldLabel(tiny, charCount: 20))
        // 3-hour arc (~70pt) easily carries a normal title.
        let big = SectographItem(id: "b", startMinute: 600, endMinute: 780)
        XCTAssertTrue(layout.shouldLabel(big, charCount: 10))
        // Instant items are never labelled (they get a marker chip instead).
        let instant = SectographItem(id: "i", startMinute: 600, endMinute: 780, kind: .instant)
        XCTAssertFalse(layout.shouldLabel(instant, charCount: 10))
        // Empty title → no label.
        XCTAssertFalse(layout.shouldLabel(big, charCount: 0))
    }

    func testTextNeedsFlip() {
        XCTAssertTrue(layout.textNeedsFlip(at: layout.angle(forMinute: 1080)))  // 6pm, left half
        XCTAssertFalse(layout.textNeedsFlip(at: layout.angle(forMinute: 360)))  // 6am, right half
    }

    func testContainsMinuteWrap() {
        let night = SectographItem(id: "n", startMinute: 1380, endMinute: 60) // 11pm–1am
        XCTAssertTrue(layout.contains(minute: 1410, night))  // 11:30pm
        XCTAssertTrue(layout.contains(minute: 30, night))    // 12:30am
        XCTAssertFalse(layout.contains(minute: 120, night))  // 2am
        let day = SectographItem(id: "d", startMinute: 600, endMinute: 660)
        XCTAssertTrue(layout.contains(minute: 630, day))
        XCTAssertFalse(layout.contains(minute: 700, day))
    }

    func testNewFieldDefaults() {
        let span = SectographItem(id: "s", startMinute: 600, endMinute: 660)
        XCTAssertEqual(span.kind, .span)
        XCTAssertFalse(span.isInstant)
        XCTAssertNil(span.symbolName)
        XCTAssertFalse(span.isDone)
        // Explicit instant, and a zero-duration span, both read as instant.
        XCTAssertTrue(SectographItem(id: "i", startMinute: 600, endMinute: 780, kind: .instant).isInstant)
        XCTAssertTrue(SectographItem(id: "z", startMinute: 600, endMinute: 600).isInstant)
    }
}
