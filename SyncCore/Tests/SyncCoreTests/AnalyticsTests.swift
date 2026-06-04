import XCTest
@testable import SyncCore

final class AnalyticsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)!
    }

    func testCompletion() {
        let now = date("2026-06-10T12:00:00.000Z")
        let range = DateInterval(start: date("2026-06-01T00:00:00.000Z"), end: date("2026-06-30T23:59:59.000Z"))
        let tasks = [
            // completed on time
            TaskStat(id: "a", isDone: true, createdAt: date("2026-06-02T09:00:00.000Z"),
                     dueAt: date("2026-06-05T00:00:00.000Z"), completedAt: date("2026-06-04T10:00:00.000Z")),
            // completed late
            TaskStat(id: "b", isDone: true, createdAt: date("2026-06-02T09:00:00.000Z"),
                     dueAt: date("2026-06-03T00:00:00.000Z"), completedAt: date("2026-06-06T10:00:00.000Z")),
            // open + overdue
            TaskStat(id: "c", isDone: false, createdAt: date("2026-06-02T09:00:00.000Z"),
                     dueAt: date("2026-06-08T00:00:00.000Z")),
            // open, not due
            TaskStat(id: "d", isDone: false, createdAt: date("2026-06-09T09:00:00.000Z")),
        ]
        let c = Analytics.completion(tasks, in: range, now: now)
        XCTAssertEqual(c.created, 4)
        XCTAssertEqual(c.completed, 2)
        XCTAssertEqual(c.overdue, 1) // only c (d isn't due)
        XCTAssertEqual(c.completionRatePct, 50) // 2/4
        XCTAssertEqual(c.onTimePct, 50) // 1 of 2 with-due completed on time
    }

    func testProductivityByHourAndPeak() {
        let tasks = [
            TaskStat(id: "a", isDone: true, createdAt: date("2026-06-01T00:00:00.000Z"), completedAt: date("2026-06-01T09:30:00.000Z")),
            TaskStat(id: "b", isDone: true, createdAt: date("2026-06-01T00:00:00.000Z"), completedAt: date("2026-06-02T09:45:00.000Z")),
            TaskStat(id: "c", isDone: true, createdAt: date("2026-06-01T00:00:00.000Z"), completedAt: date("2026-06-03T14:00:00.000Z")),
            TaskStat(id: "d", isDone: false, createdAt: date("2026-06-01T00:00:00.000Z")),
        ]
        let hours = Analytics.productivityByHour(tasks, calendar: cal)
        XCTAssertEqual(hours[9], 2)
        XCTAssertEqual(hours[14], 1)
        XCTAssertEqual(Analytics.peakHour(tasks, calendar: cal), 9)
    }

    func testPeakHourNilWithoutData() {
        let tasks = [TaskStat(id: "a", isDone: false, createdAt: date("2026-06-01T00:00:00.000Z"))]
        XCTAssertNil(Analytics.peakHour(tasks, calendar: cal))
    }

    func testTimeByList() {
        let tasks = [
            TaskStat(id: "a", isDone: true, createdAt: date("2026-06-01T00:00:00.000Z"), actualMinutes: 60, listId: "work"),
            TaskStat(id: "b", isDone: true, createdAt: date("2026-06-01T00:00:00.000Z"),
                     scheduledStart: date("2026-06-01T09:00:00.000Z"), scheduledEnd: date("2026-06-01T09:30:00.000Z"), listId: "work"),
            TaskStat(id: "c", isDone: true, createdAt: date("2026-06-01T00:00:00.000Z"), actualMinutes: 45, listId: "home"),
            TaskStat(id: "d", isDone: false, createdAt: date("2026-06-01T00:00:00.000Z")), // no time → skipped
        ]
        let slices = Analytics.timeByList(tasks)
        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices[0].listId, "work") // 60 + 30 = 90, the largest
        XCTAssertEqual(slices[0].minutes, 90)
        XCTAssertEqual(slices[1].minutes, 45)
    }

    func testBacklog() {
        let now = date("2026-06-10T00:00:00.000Z")
        let tasks = [
            TaskStat(id: "a", isDone: false, createdAt: date("2026-06-01T00:00:00.000Z")), // age 9
            TaskStat(id: "b", isDone: false, createdAt: date("2026-06-09T00:00:00.000Z"), dueAt: date("2026-06-05T00:00:00.000Z")), // age 1, overdue
            TaskStat(id: "c", isDone: false, createdAt: date("2026-06-05T00:00:00.000Z")), // age 5
            TaskStat(id: "done", isDone: true, createdAt: date("2026-06-01T00:00:00.000Z"), completedAt: now),
        ]
        let b = Analytics.backlog(tasks, now: now)
        XCTAssertEqual(b.inbox, 3) // open only
        XCTAssertEqual(b.overdue, 1)
        XCTAssertEqual(b.medianAgeDays, 5) // ages [1,5,9] → median 5
    }

    func testFocus() {
        let tasks = [
            TaskStat(id: "a", isDone: true, createdAt: date("2026-06-01T00:00:00.000Z"), actualMinutes: 25),
            TaskStat(id: "b", isDone: true, createdAt: date("2026-06-01T00:00:00.000Z"), actualMinutes: 50),
            TaskStat(id: "c", isDone: false, createdAt: date("2026-06-01T00:00:00.000Z")), // no focus
        ]
        let f = Analytics.focus(tasks)
        XCTAssertEqual(f.totalMinutes, 75)
        XCTAssertEqual(f.sessions, 2)
        XCTAssertEqual(f.avgMinutes, 37) // 75/2 = 37 (int)
    }
}
