import XCTest
@testable import SyncCore

final class RoutineMaterializerTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func testOccursOnMatchingWeekday() {
        let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let weekday = cal.component(.weekday, from: date)
        XCTAssertTrue(RoutineMaterializer.occurs(recurrence: RoutineRecurrence(weekdays: [weekday]), on: date, calendar: cal))
        let other = weekday == 1 ? 2 : 1
        XCTAssertFalse(RoutineMaterializer.occurs(recurrence: RoutineRecurrence(weekdays: [other]), on: date, calendar: cal))
    }

    func testOccursEveryNDaysAlternates() {
        let d0 = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let d1 = cal.date(byAdding: .day, value: 1, to: d0)!
        let occ0 = RoutineMaterializer.occurs(recurrence: RoutineRecurrence(everyNDays: 2), on: d0, calendar: cal)
        let occ1 = RoutineMaterializer.occurs(recurrence: RoutineRecurrence(everyNDays: 2), on: d1, calendar: cal)
        XCTAssertNotEqual(occ0, occ1)
    }

    func testNilRecurrenceIsDaily() {
        let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        XCTAssertTrue(RoutineMaterializer.occurs(recurrence: nil, on: date, calendar: cal))
    }

    func testInstancesLayOutSequentiallyFromAnchor() {
        let steps = [
            RoutineStep(title: "Meditate", minutes: 10, ord: 0),
            RoutineStep(title: "Gym", minutes: 60, ord: 1),
            RoutineStep(title: "Read", minutes: 30, ord: 2),
        ]
        let inst = RoutineMaterializer.instances(steps: steps, anchorTime: "06:30")
        XCTAssertEqual(inst.map(\.startMinute), [390, 400, 460]) // 6:30, 6:40, 7:40
        XCTAssertEqual(inst.map(\.endMinute), [400, 460, 490])
        XCTAssertEqual(inst.map(\.title), ["Meditate", "Gym", "Read"])
    }

    func testInstancesSortByOrdAndDefaultAnchor() {
        let inst = RoutineMaterializer.instances(
            steps: [RoutineStep(title: "b", minutes: 30, ord: 1), RoutineStep(title: "a", minutes: 15, ord: 0)],
            anchorTime: nil
        )
        XCTAssertEqual(inst.map(\.title), ["a", "b"]) // sorted by ord
        XCTAssertEqual(inst.first?.startMinute, 540)   // default 9:00
    }

    func testParseAnchorMinute() {
        XCTAssertEqual(RoutineMaterializer.parseAnchorMinute("06:30"), 390)
        XCTAssertEqual(RoutineMaterializer.parseAnchorMinute("6:30"), 390)
        XCTAssertNil(RoutineMaterializer.parseAnchorMinute("25:00"))
        XCTAssertNil(RoutineMaterializer.parseAnchorMinute("abc"))
        XCTAssertNil(RoutineMaterializer.parseAnchorMinute(nil))
    }
}
