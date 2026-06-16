import XCTest
@testable import SyncCore

final class AgendaSnapshotTests: XCTestCase {
    private let suite = "AgendaSnapshotTests.suite"

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testRoundTripsThroughUserDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let snapshot = AgendaSnapshot(items: [
            AgendaItem(taskId: "t1", title: "Standup", dueText: "9:00 AM", isDone: false, priorityLevel: 4),
            AgendaItem(taskId: "t2", title: "Pay rent", dueText: nil, isDone: true, priorityLevel: 0),
        ], generatedAtEpoch: 1_700_000_000)

        AgendaSnapshotStore.save(snapshot, to: defaults)
        let loaded = AgendaSnapshotStore.load(from: defaults)
        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.items.first?.priorityLevel, 4)
    }

    func testLoadMissingReturnsEmpty() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(AgendaSnapshotStore.load(from: defaults), .empty)
    }

    func testEnrichedFieldsRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let snapshot = AgendaSnapshot(
            items: [AgendaItem(taskId: "t1", title: "Deep work", startMinute: 540, endMinute: 660, colorHex: "#378ADD")],
            generatedAtEpoch: 1_700_000_000, completedToday: 4, totalToday: 9, focusMinutesToday: 95,
            topHabit: HabitSummary(name: "Workout", streakCurrent: 7, recent: [true, true, false, true, true, true, true]))
        AgendaSnapshotStore.save(snapshot, to: defaults)
        let loaded = AgendaSnapshotStore.load(from: defaults)
        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.items.first?.colorHex, "#378ADD")
        XCTAssertEqual(loaded.completedToday, 4)
        XCTAssertEqual(loaded.topHabit?.streakCurrent, 7)
    }

    /// A snapshot written by an older app build (no enriched keys, no item colorHex) must still decode,
    /// defaulting the new fields rather than throwing.
    func testDecodesLegacySnapshotWithoutEnrichedKeys() throws {
        let legacy = """
        {"items":[{"taskId":"t1","title":"Old","isDone":false,"priorityLevel":2}],"generatedAtEpoch":1700000000}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AgendaSnapshot.self, from: legacy)
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertNil(decoded.items.first?.colorHex)
        XCTAssertEqual(decoded.completedToday, 0)
        XCTAssertEqual(decoded.totalToday, 0)
        XCTAssertEqual(decoded.focusMinutesToday, 0)
        XCTAssertNil(decoded.topHabit)
    }
}
