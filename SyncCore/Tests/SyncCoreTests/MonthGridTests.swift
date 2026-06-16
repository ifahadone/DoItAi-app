import XCTest
@testable import SyncCore

final class MonthGridTests: XCTestCase {
    /// Sunday-first UTC calendar for deterministic grids.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1 // Sunday
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testGridIsSixWeeksOfSeven() {
        let grid = MonthGridBuilder.make(for: date(2026, 6, 15), calendar: cal)
        XCTAssertEqual(grid.weeks.count, 6)
        XCTAssertTrue(grid.weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(grid.weekdaySymbols.count, 7)
    }

    func testJune2026FirstCellAndInMonthFlags() {
        // June 1 2026 is a Monday; Sunday-first grid starts on Sun May 31.
        let grid = MonthGridBuilder.make(for: date(2026, 6, 10), calendar: cal)
        XCTAssertEqual(grid.weeks[0][0].date, date(2026, 5, 31))
        XCTAssertFalse(grid.weeks[0][0].inMonth)            // May 31 spills in
        XCTAssertEqual(grid.weeks[0][1].date, date(2026, 6, 1))
        XCTAssertTrue(grid.weeks[0][1].inMonth)             // June 1
        XCTAssertEqual(grid.monthStart, date(2026, 6, 1))
    }

    func testInMonthDayCountMatchesMonthLength() {
        // June has 30 days; exactly 30 cells should be inMonth.
        let grid = MonthGridBuilder.make(for: date(2026, 6, 1), calendar: cal)
        let inMonth = grid.weeks.flatMap { $0 }.filter { $0.inMonth }.count
        XCTAssertEqual(inMonth, 30)
    }

    func testMondayFirstCalendarShiftsHeaderAndGrid() {
        var monFirst = cal
        monFirst.firstWeekday = 2 // Monday
        let grid = MonthGridBuilder.make(for: date(2026, 6, 10), calendar: monFirst)
        // June 1 is a Monday, so a Monday-first grid starts exactly on June 1.
        XCTAssertEqual(grid.weeks[0][0].date, date(2026, 6, 1))
        XCTAssertTrue(grid.weeks[0][0].inMonth)
    }
}
