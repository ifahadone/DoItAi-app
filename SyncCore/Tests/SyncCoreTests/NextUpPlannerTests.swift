import XCTest
@testable import SyncCore

final class NextUpPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000) // fixed reference
    private func mins(_ n: Double) -> Date { now.addingTimeInterval(n * 60) }

    func testCurrentBlockDetected() {
        let items = [
            AgendaSlotItem(id: "a", title: "Focus", start: mins(-30), end: mins(30)),
            AgendaSlotItem(id: "b", title: "Lunch", start: mins(90), end: mins(150)),
        ]
        let r = NextUpPlanner.compute(items, now: now)
        XCTAssertEqual(r.current?.id, "a")
        XCTAssertEqual(r.next?.id, "b")
        XCTAssertEqual(NextUpPlanner.minutesLeft(in: r.current!, now: now), 30)
    }

    func testNextPrefersSoonestAnchorAcrossScheduledAndDue() {
        let items = [
            AgendaSlotItem(id: "due", title: "Call", due: mins(20)),
            AgendaSlotItem(id: "block", title: "Review", start: mins(45), end: mins(75)),
        ]
        let r = NextUpPlanner.compute(items, now: now)
        XCTAssertNil(r.current)
        XCTAssertEqual(r.next?.id, "due") // due in 20m beats a block in 45m
    }

    func testNoCurrentNoFuture() {
        let items = [AgendaSlotItem(id: "past", title: "Done thing", start: mins(-120), end: mins(-60))]
        let r = NextUpPlanner.compute(items, now: now)
        XCTAssertNil(r.current)
        XCTAssertNil(r.next)
    }

    func testCurrentExcludedFromNext() {
        let items = [
            AgendaSlotItem(id: "a", title: "Now", start: mins(-10), end: mins(50)),
            AgendaSlotItem(id: "b", title: "Later", start: mins(120), end: mins(180)),
        ]
        let r = NextUpPlanner.compute(items, now: now)
        XCTAssertEqual(r.current?.id, "a")
        XCTAssertEqual(r.next?.id, "b") // the current block is not also returned as next
    }
}
