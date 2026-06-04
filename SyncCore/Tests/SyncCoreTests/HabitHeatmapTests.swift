import XCTest
@testable import SyncCore

final class HabitHeatmapTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func testWindowOrderingAndCompletion() {
        let today = cal.date(from: DateComponents(year: 2026, month: 6, day: 4))!
        let completions: Set<String> = ["2026-06-04", "2026-06-02"]
        let days = HabitHeatmap.days(completions: completions, days: 7, today: today, calendar: cal)

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.dayOffset, -6) // oldest first
        XCTAssertEqual(days.last?.dayOffset, 0)   // today last
        XCTAssertEqual(days.last?.dateString, "2026-06-04")
        XCTAssertTrue(days.last!.completed)                                     // today
        XCTAssertTrue(days.first(where: { $0.dayOffset == -2 })!.completed)     // 06-02
        XCTAssertFalse(days.first(where: { $0.dayOffset == -1 })!.completed)    // 06-03 missed
        XCTAssertEqual(HabitHeatmap.completedCount(in: days), 2)
    }

    func testEmptyWindow() {
        XCTAssertTrue(HabitHeatmap.days(completions: ["2026-06-04"], days: 0, today: Date(), calendar: cal).isEmpty)
    }

    func testNoCompletions() {
        let today = cal.date(from: DateComponents(year: 2026, month: 6, day: 4))!
        let days = HabitHeatmap.days(completions: [], days: 5, today: today, calendar: cal)
        XCTAssertEqual(days.count, 5)
        XCTAssertEqual(HabitHeatmap.completedCount(in: days), 0)
    }
}
