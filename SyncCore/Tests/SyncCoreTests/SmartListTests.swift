import XCTest
@testable import SyncCore

/// Golden-fixture test for the smart-list partition (DevelopmentPlan P1-G DoD). A fixed `now` + a UTC
/// calendar make the day boundaries deterministic. Asserts each fixture task lands in the expected
/// bucket AND that the active tasks form a total, mutually-exclusive partition.
final class SmartListTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    // 2023-11-14T22:13:20Z — mid-day UTC so "today" has room on both sides.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    private func classify(_ status: TaskStatus, due: Date? = nil, sched: Date? = nil) -> SmartList? {
        SmartListClassifier.classify(status: status, dueAt: due, scheduledStart: sched, now: now, calendar: calendar)
    }

    func testEachBucket() {
        XCTAssertEqual(classify(.scheduled, due: now - day), .overdue, "due yesterday → Overdue")
        XCTAssertEqual(classify(.inProgress, due: now), .today, "due now → Today")
        XCTAssertEqual(classify(.scheduled, sched: now + 2 * day), .upcoming, "scheduled in 2d → Upcoming")
        XCTAssertEqual(classify(.scheduled), .anytime, "committed but undated → Anytime")
        XCTAssertEqual(classify(.inbox), .someday, "untriaged + undated → Someday")
    }

    func testTerminalStatesBelongToNoSmartList() {
        XCTAssertNil(classify(.done, due: now))
        XCTAssertNil(classify(.cancelled, due: now - day))
    }

    func testEarliestDateWins() {
        // A far-future due date but an overdue scheduledStart ⇒ Overdue (earliest wins).
        XCTAssertEqual(classify(.scheduled, due: now + 5 * day, sched: now - day), .overdue)
    }

    func testDayBoundariesAreInclusiveOfToday() {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = startOfToday + day - 1
        XCTAssertEqual(classify(.scheduled, due: startOfToday), .today, "00:00 today → Today")
        XCTAssertEqual(classify(.scheduled, due: endOfToday), .today, "23:59:59 today → Today")
        XCTAssertEqual(classify(.scheduled, due: startOfToday - 1), .overdue, "one second before today → Overdue")
    }

    /// The partition is total + mutually exclusive: every active fixture task classifies to exactly one
    /// bucket, and across the fixture all five buckets are exercised.
    func testActiveTasksFormATotalExclusivePartition() {
        let fixture: [(TaskStatus, Date?, Date?)] = [
            (.scheduled, now - 3 * day, nil),   // overdue
            (.inProgress, now, nil),            // today
            (.scheduled, now + day, nil),       // upcoming
            (.scheduled, nil, nil),             // anytime
            (.inbox, nil, nil),                 // someday
            (.inProgress, now + 10 * day, nil), // upcoming
        ]
        var seen = Set<SmartList>()
        for (status, due, sched) in fixture {
            let bucket = SmartListClassifier.classify(status: status, dueAt: due, scheduledStart: sched, now: now, calendar: calendar)
            XCTAssertNotNil(bucket, "active task must classify into exactly one bucket")
            if let bucket { seen.insert(bucket) }
        }
        XCTAssertEqual(seen, Set(SmartList.allCases), "the fixture should exercise all five smart lists")
    }
}
