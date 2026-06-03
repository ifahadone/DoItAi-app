import XCTest
@testable import SyncCore

final class DTOCodableTests: XCTestCase {
    private let encoder = JSONCoding.makeEncoder()
    private let decoder = JSONCoding.makeDecoder()

    // Fixed instants so tests are deterministic.
    private let created = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
    private let updated = Date(timeIntervalSince1970: 1_700_000_500)

    // MARK: Enum raw values are part of the contract

    func testEnumRawValuesMatchContract() {
        XCTAssertEqual(TaskStatus.inbox.rawValue, 0)
        XCTAssertEqual(TaskStatus.scheduled.rawValue, 1)
        XCTAssertEqual(TaskStatus.inProgress.rawValue, 2)
        XCTAssertEqual(TaskStatus.done.rawValue, 3)
        XCTAssertEqual(TaskStatus.cancelled.rawValue, 4)

        XCTAssertEqual(Priority.none.rawValue, 0)
        XCTAssertEqual(Priority.p4.rawValue, 1)
        XCTAssertEqual(Priority.p3.rawValue, 2)
        XCTAssertEqual(Priority.p2.rawValue, 3)
        XCTAssertEqual(Priority.p1.rawValue, 4)

        XCTAssertEqual(Energy.low.rawValue, 0)
        XCTAssertEqual(Energy.med.rawValue, 1)
        XCTAssertEqual(Energy.high.rawValue, 2)
    }

    func testStatusEncodesAsInteger() throws {
        let data = try encoder.encode(TaskStatus.inProgress)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "2")
    }

    // MARK: TaskDTO round-trip

    func testFullTaskDTORoundTrips() throws {
        let task = TaskDTO(
            id: "11111111-1111-1111-1111-111111111111",
            ownerId: "22222222-2222-2222-2222-222222222222",
            listId: "33333333-3333-3333-3333-333333333333",
            parentTaskId: nil,
            title: "Lunch with Sam",
            notes: "bring the **deck**",
            status: .scheduled,
            priority: .p2,
            rank: 5,
            energy: .med,
            dueAt: updated,
            scheduledStart: created,
            scheduledEnd: updated,
            estimatedMinutes: 60,
            actualMinutes: nil,
            isAllDay: false,
            recurrence: RecurrenceRule(freq: .weekly, interval: 1, byWeekday: [2, 4, 6]),
            recurrenceParentId: nil,
            routineInstanceOf: nil,
            assigneeUserId: "44444444-4444-4444-4444-444444444444",
            location: GeoPoint(lat: 37.33, lon: -122.03, name: "Caffè"),
            url: "https://example.com",
            tagIds: ["tag-a", "tag-b"],
            createdAt: created,
            updatedAt: updated,
            completedAt: nil,
            archived: false,
            serverVersion: 7,
            deletedAt: nil
        )

        let data = try encoder.encode(task)
        let decoded = try decoder.decode(TaskDTO.self, from: data)
        XCTAssertEqual(decoded, task)
    }

    func testMinimalTaskDTORoundTrips() throws {
        let task = TaskDTO(
            id: "id-1",
            ownerId: "owner-1",
            title: "Inbox item",
            createdAt: created,
            updatedAt: updated
        )
        let decoded = try decoder.decode(TaskDTO.self, from: try encoder.encode(task))
        XCTAssertEqual(decoded, task)
        XCTAssertEqual(decoded.status, .inbox)
        XCTAssertEqual(decoded.priority, .none)
        XCTAssertEqual(decoded.tagIds, [])
        XCTAssertFalse(decoded.isAllDay)
    }

    func testDateEncodesAsRFC3339UTC() throws {
        let task = TaskDTO(id: "x", ownerId: "o", title: "t", createdAt: created, updatedAt: updated)
        let object = try JSONSerialization.jsonObject(with: try encoder.encode(task)) as? [String: Any]
        XCTAssertEqual(object?["createdAt"] as? String, "2023-11-14T22:13:20Z")
    }

    func testDecodesFractionalSecondsFromServer() throws {
        // Server may include fractional seconds; the decoder must tolerate them.
        let json = """
        { "id":"x","ownerId":"o","title":"t","status":0,"priority":0,"rank":0,"isAllDay":false,
          "tagIds":[],"archived":false,"serverVersion":1,
          "createdAt":"2026-06-03T08:30:00.123Z","updatedAt":"2026-06-03T08:30:00Z" }
        """
        let task = try decoder.decode(TaskDTO.self, from: Data(json.utf8))
        XCTAssertEqual(task.title, "t")
        XCTAssertNotNil(task.createdAt)
    }

    // MARK: List & Tag

    func testTaskListDTORoundTrips() throws {
        let list = TaskListDTO(
            id: "l1", ownerId: "o1", name: "Work", colorHex: "#FF0000", icon: "briefcase",
            sortIndex: 2, shareId: "s1", createdAt: created, updatedAt: updated, serverVersion: 3
        )
        XCTAssertEqual(try decoder.decode(TaskListDTO.self, from: try encoder.encode(list)), list)
    }

    func testTagDTORoundTrips() throws {
        let tag = TagDTO(
            id: "t1", ownerId: "o1", name: "deep-work", colorHex: "#00FF00",
            createdAt: created, updatedAt: updated, serverVersion: 1
        )
        XCTAssertEqual(try decoder.decode(TagDTO.self, from: try encoder.encode(tag)), tag)
    }

    func testRecurrenceRuleRoundTrips() throws {
        let rule = RecurrenceRule(freq: .weekly, interval: 2, byWeekday: [2, 4, 6], byMonthDay: nil, count: 10, until: updated)
        XCTAssertEqual(try decoder.decode(RecurrenceRule.self, from: try encoder.encode(rule)), rule)
    }

    // MARK: Forward-compat — unknown fields ignored

    func testUnknownServerFieldsAreIgnored() throws {
        let json = """
        { "id":"x","ownerId":"o","title":"t","status":0,"priority":0,"rank":0,"isAllDay":false,
          "tagIds":[],"archived":false,"serverVersion":1,
          "createdAt":"2023-11-14T22:13:20Z","updatedAt":"2023-11-14T22:13:20Z",
          "futureFieldFromNewerServer": { "anything": [1,2,3] } }
        """
        let task = try decoder.decode(TaskDTO.self, from: Data(json.utf8))
        XCTAssertEqual(task.id, "x")
    }

    func testUnknownEntityTypeDecodesAsUnknown() {
        XCTAssertEqual(SyncEntityType(rawValue: "comment"), .unknown("comment"))
        XCTAssertEqual(SyncEntityType.task.rawValue, "task")
    }
}
