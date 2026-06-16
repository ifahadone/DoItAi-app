import XCTest
@testable import SyncCore

final class ReschedulePresetTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    /// 2026-06-03 is a Wednesday; 06:00 UTC so all day-level presets are in the future.
    private var wedMorning: Date {
        utc.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 6))!
    }
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testTomorrowIsNextDayAt9() {
        XCTAssertEqual(ReschedulePreset.tomorrow.date(from: wedMorning, calendar: utc), at(2026, 6, 4, 9))
    }

    func testThisEveningIsTodayAt19() {
        XCTAssertEqual(ReschedulePreset.thisEvening.date(from: wedMorning, calendar: utc), at(2026, 6, 3, 19))
    }

    func testThisWeekendIsUpcomingSaturday() {
        // Wed 06-03 → Sat 06-06 at 09:00.
        XCTAssertEqual(ReschedulePreset.thisWeekend.date(from: wedMorning, calendar: utc), at(2026, 6, 6, 9))
    }

    func testNextWeekIsUpcomingMonday() {
        // Wed 06-03 → Mon 06-08 at 09:00.
        XCTAssertEqual(ReschedulePreset.nextWeek.date(from: wedMorning, calendar: utc), at(2026, 6, 8, 9))
    }

    func testNextWeekFromMondayIsFollowingMonday() {
        // 2026-06-01 is a Monday → next week's Monday is 06-08, not today.
        let mon = at(2026, 6, 1, 6)
        XCTAssertEqual(ReschedulePreset.nextWeek.date(from: mon, calendar: utc), at(2026, 6, 8, 9))
    }

    func testThisEveningReturnsNilWhenPast() {
        // At 21:00, "this evening" (19:00) is already past → nil.
        let lateNight = at(2026, 6, 3, 21)
        XCTAssertNil(ReschedulePreset.thisEvening.date(from: lateNight, calendar: utc))
    }

    func testLaterTodayIsThreeHoursOutOnTheHour() {
        XCTAssertEqual(ReschedulePreset.laterToday.date(from: wedMorning, calendar: utc), at(2026, 6, 3, 9))
    }
}
