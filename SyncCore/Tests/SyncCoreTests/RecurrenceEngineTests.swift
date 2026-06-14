import XCTest
@testable import SyncCore

final class RecurrenceEngineTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testDailyAdvancesOneDay() {
        let next = RecurrenceEngine.nextOccurrence(after: date(2026, 6, 1), rule: RecurrenceRule(freq: .daily), calendar: utc)
        XCTAssertEqual(next, date(2026, 6, 2))
    }

    func testWeeklyEveryTwoWeeks() {
        let next = RecurrenceEngine.nextOccurrence(after: date(2026, 6, 1), rule: RecurrenceRule(freq: .weekly, interval: 2), calendar: utc)
        XCTAssertEqual(next, date(2026, 6, 15))
    }

    func testMonthlyAdvancesOneMonth() {
        let next = RecurrenceEngine.nextOccurrence(after: date(2026, 1, 15), rule: RecurrenceRule(freq: .monthly), calendar: utc)
        XCTAssertEqual(next, date(2026, 2, 15))
    }

    func testYearlyAdvancesOneYear() {
        let next = RecurrenceEngine.nextOccurrence(after: date(2026, 6, 1), rule: RecurrenceRule(freq: .yearly), calendar: utc)
        XCTAssertEqual(next, date(2027, 6, 1))
    }

    func testUntilBoundStopsRecurrence() {
        let rule = RecurrenceRule(freq: .daily, until: date(2026, 6, 1))
        XCTAssertNil(RecurrenceEngine.nextOccurrence(after: date(2026, 6, 1), rule: rule, calendar: utc))
    }
}
