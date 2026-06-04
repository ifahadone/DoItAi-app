import XCTest
@testable import SyncCore

final class CalendarSyncPlannerTests: XCTestCase {
    private func block(_ id: String, _ title: String, start: Double = 100, end: Double = 200) -> CalendarExportBlock {
        CalendarExportBlock(taskId: id, title: title, startEpoch: start, endEpoch: end)
    }

    func testFreshExportCreatesAll() {
        let plan = CalendarSyncPlanner.plan(blocks: [block("a", "Gym"), block("b", "Read")], existing: [])
        XCTAssertEqual(plan.creates.map(\.taskId), ["a", "b"])
        XCTAssertTrue(plan.updates.isEmpty)
        XCTAssertTrue(plan.deletes.isEmpty)
    }

    func testUnchangedBlockYieldsEmptyPlan() {
        let a = block("a", "Gym")
        let existing = [ExportedEventRef(taskId: "a", eventId: "evt-a", contentHash: a.contentHash)]
        let plan = CalendarSyncPlanner.plan(blocks: [a], existing: existing)
        XCTAssertTrue(plan.isEmpty, "re-exporting identical content must be a no-op (idempotent)")
    }

    func testChangedContentYieldsUpdateWithSameEventId() {
        let old = block("a", "Gym", start: 100, end: 200)
        let existing = [ExportedEventRef(taskId: "a", eventId: "evt-a", contentHash: old.contentHash)]
        let moved = block("a", "Gym", start: 150, end: 250) // rescheduled
        let plan = CalendarSyncPlanner.plan(blocks: [moved], existing: existing)
        XCTAssertEqual(plan.creates.count, 0)
        XCTAssertEqual(plan.updates.count, 1)
        XCTAssertEqual(plan.updates.first?.eventId, "evt-a") // reuse the event, don't recreate
        XCTAssertEqual(plan.updates.first?.block.startEpoch, 150)
        XCTAssertTrue(plan.deletes.isEmpty)
    }

    func testRemovedBlockYieldsDelete() {
        let a = block("a", "Gym")
        let existing = [
            ExportedEventRef(taskId: "a", eventId: "evt-a", contentHash: a.contentHash),
            ExportedEventRef(taskId: "b", eventId: "evt-b", contentHash: "stale"),
        ]
        let plan = CalendarSyncPlanner.plan(blocks: [a], existing: existing) // b no longer scheduled
        XCTAssertTrue(plan.isEmpty == false)
        XCTAssertEqual(plan.deletes, ["evt-b"])
        XCTAssertTrue(plan.creates.isEmpty)
        XCTAssertTrue(plan.updates.isEmpty)
    }

    func testMixedCreateUpdateDelete() {
        let kept = block("keep", "Keep", start: 100, end: 200)
        let changed = block("chg", "Changed", start: 300, end: 400)
        let existing = [
            ExportedEventRef(taskId: "keep", eventId: "evt-keep", contentHash: kept.contentHash),
            ExportedEventRef(taskId: "chg", eventId: "evt-chg", contentHash: "old-hash"),
            ExportedEventRef(taskId: "gone", eventId: "evt-gone", contentHash: "whatever"),
        ]
        let plan = CalendarSyncPlanner.plan(blocks: [kept, changed, block("new", "New")], existing: existing)
        XCTAssertEqual(plan.creates.map(\.taskId), ["new"])
        XCTAssertEqual(plan.updates.map(\.eventId), ["evt-chg"])
        XCTAssertEqual(plan.deletes, ["evt-gone"])
    }
}
