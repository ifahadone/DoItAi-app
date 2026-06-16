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

    // MARK: - FR-RECUR-050: byWeekday / byMonthDay / count expansion

    func testByWeekdaySameWeekNextDay() {
        // 2026-06-01 is a Monday; weekly on Mon/Wed/Fri -> next is Wed 2026-06-03.
        let rule = RecurrenceRule(freq: .weekly, byWeekday: [2, 4, 6]) // 2=Mon,4=Wed,6=Fri
        XCTAssertEqual(RecurrenceEngine.nextOccurrence(after: date(2026, 6, 1), rule: rule, calendar: utc), date(2026, 6, 3))
    }

    func testByWeekdayWrapsToNextWeek() {
        // From Fri 2026-06-05, Mon/Wed/Fri -> next is Mon 2026-06-08.
        let rule = RecurrenceRule(freq: .weekly, byWeekday: [2, 4, 6])
        XCTAssertEqual(RecurrenceEngine.nextOccurrence(after: date(2026, 6, 5), rule: rule, calendar: utc), date(2026, 6, 8))
    }

    func testByWeekdayEveryTwoWeeksSkipsOffWeek() {
        // Every 2 weeks on Monday from Mon 2026-06-01 -> skip 06-08, land 06-15.
        let rule = RecurrenceRule(freq: .weekly, interval: 2, byWeekday: [2])
        XCTAssertEqual(RecurrenceEngine.nextOccurrence(after: date(2026, 6, 1), rule: rule, calendar: utc), date(2026, 6, 15))
    }

    func testByMonthDayPicksNextMatchingDay() {
        // Monthly on the 1st and 15th; from the 1st -> the 15th.
        let rule = RecurrenceRule(freq: .monthly, byMonthDay: [1, 15])
        XCTAssertEqual(RecurrenceEngine.nextOccurrence(after: date(2026, 6, 1), rule: rule, calendar: utc), date(2026, 6, 15))
    }

    func testByMonthDayNegativeIsLastDay() {
        // -1 = last day of the month; from 2026-06-10 -> 2026-06-30.
        let rule = RecurrenceRule(freq: .monthly, byMonthDay: [-1])
        XCTAssertEqual(RecurrenceEngine.nextOccurrence(after: date(2026, 6, 10), rule: rule, calendar: utc), date(2026, 6, 30))
    }

    func testCountBoundStopsSeries() {
        let rule = RecurrenceRule(freq: .daily, count: 3)
        XCTAssertNotNil(RecurrenceEngine.nextOccurrence(after: date(2026, 6, 1), rule: rule, calendar: utc, occurrencesSoFar: 2))
        XCTAssertNil(RecurrenceEngine.nextOccurrence(after: date(2026, 6, 1), rule: rule, calendar: utc, occurrencesSoFar: 3))
    }
}
