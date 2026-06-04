import XCTest
@testable import DesignSystem

final class CalendarBusyTests: XCTestCase {
    private let dayStart: Double = 1_700_000_000 // treat as local midnight for the test
    private func hours(_ h: Double) -> Double { dayStart + h * 3600 }

    func testEventBecomesBusyBlock() {
        let events = [CalendarEvent(id: "e1", title: "Meeting", startEpoch: hours(9), endEpoch: hours(10.5))]
        let items = CalendarBusyMapper.busyItems(from: events, dayStartEpoch: dayStart)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].startMinute, 540)  // 9:00
        XCTAssertEqual(items[0].endMinute, 630)    // 10:30
        XCTAssertEqual(items[0].id, "busy:e1")
    }

    func testAllDayEventSkipped() {
        let events = [CalendarEvent(id: "e", title: "Holiday", startEpoch: dayStart, endEpoch: dayStart + 86_400, isAllDay: true)]
        XCTAssertTrue(CalendarBusyMapper.busyItems(from: events, dayStartEpoch: dayStart).isEmpty)
    }

    func testClampsToDayBounds() {
        let overnight = CalendarEvent(id: "o", title: "Red-eye", startEpoch: dayStart - 3600, endEpoch: hours(1))
        let items = CalendarBusyMapper.busyItems(from: [overnight], dayStartEpoch: dayStart)
        XCTAssertEqual(items.first?.startMinute, 0)
        XCTAssertEqual(items.first?.endMinute, 60)

        let late = CalendarEvent(id: "l", title: "Party", startEpoch: hours(23), endEpoch: hours(26))
        let lateItems = CalendarBusyMapper.busyItems(from: [late], dayStartEpoch: dayStart)
        XCTAssertEqual(lateItems.first?.startMinute, 1380)
        XCTAssertEqual(lateItems.first?.endMinute, 1440)
    }

    func testEventOutsideDayDropped() {
        let tomorrow = CalendarEvent(id: "t", title: "Future", startEpoch: hours(30), endEpoch: hours(31))
        XCTAssertTrue(CalendarBusyMapper.busyItems(from: [tomorrow], dayStartEpoch: dayStart).isEmpty)
    }
}
