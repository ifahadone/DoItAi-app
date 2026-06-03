import XCTest
@testable import SyncCore

final class NotificationPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func reminder(_ id: String, at: Date) -> PlannedNotification {
        PlannedNotification(reminderId: id, taskId: "t-\(id)", fireAt: at, title: "Task \(id)")
    }

    func testExcludesPastFiresAndSortsSoonestFirst() {
        let plan = NotificationPlanner.plan(
            reminders: [
                reminder("past", at: now - 60),
                reminder("c", at: now + 300),
                reminder("a", at: now + 100),
                reminder("b", at: now + 200),
            ],
            now: now
        )
        XCTAssertEqual(plan.map(\.reminderId), ["a", "b", "c"])   // past dropped, soonest first
    }

    func testCapsAtSixtyFourKeepingTheSoonest() {
        // 100 future reminders, 1 minute apart.
        let many = (0..<100).map { reminder(String(format: "%03d", $0), at: now + Double($0 + 1) * 60) }
        let plan = NotificationPlanner.plan(reminders: many.shuffled(), now: now)
        XCTAssertEqual(plan.count, 64)                    // iOS pending cap
        XCTAssertEqual(plan.first?.reminderId, "000")     // nearest
        XCTAssertEqual(plan.last?.reminderId, "063")      // 64th-nearest; 064…099 deferred to re-arm
    }

    func testEmptyAndAllPast() {
        XCTAssertTrue(NotificationPlanner.plan(reminders: [], now: now).isEmpty)
        XCTAssertTrue(NotificationPlanner.plan(reminders: [reminder("p", at: now - 1)], now: now).isEmpty)
    }
}

final class ReminderChecklistDTOTests: XCTestCase {
    private let encoder = JSONCoding.makeEncoder()
    private let decoder = JSONCoding.makeDecoder()

    func testReminderRoundTrips() throws {
        let r = ReminderDTO(
            id: "r1", ownerId: "o", taskId: "t1", kind: 0,
            fireAt: Date(timeIntervalSince1970: 1_700_003_600), offsetMinutes: nil, interruption: 1,
            notificationId: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000), serverVersion: 1
        )
        XCTAssertEqual(try decoder.decode(ReminderDTO.self, from: try encoder.encode(r)), r)
    }

    func testReminderIgnoresServerRegionKey() throws {
        // The server payload carries `region`; the DTO omits it and must still decode.
        let json = """
        { "id":"r1","ownerId":"o","taskId":"t1","kind":0,"fireAt":"2026-06-03T22:11:07.873Z",
          "region":null,"interruption":1,"offsetMinutes":null,"notificationId":null,
          "createdAt":"2026-06-03T21:11:07.990Z","updatedAt":"2026-06-03T21:11:07.990Z",
          "serverVersion":1,"deletedAt":null }
        """
        let r = try decoder.decode(ReminderDTO.self, from: Data(json.utf8))
        XCTAssertEqual(r.id, "r1")
        XCTAssertEqual(r.taskId, "t1")
        XCTAssertNotNil(r.fireAt)
    }

    func testChecklistItemRoundTrips() throws {
        let c = ChecklistItemDTO(
            id: "c1", ownerId: "o", taskId: "t1", text: "step one", done: true, ord: 2,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000), serverVersion: 3
        )
        XCTAssertEqual(try decoder.decode(ChecklistItemDTO.self, from: try encoder.encode(c)), c)
    }
}
