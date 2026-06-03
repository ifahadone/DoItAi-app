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
}
