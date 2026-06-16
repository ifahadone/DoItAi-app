import XCTest
@testable import SyncCore

final class SmartWakePlannerTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func at(_ h: Int, _ m: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: h, minute: m))!
    }

    func testWakeIsCommitmentMinusRoutineAndBuffer() {
        // 9:00 commitment, 45-min routine, 10-min buffer -> wake 08:05.
        let wake = SmartWakePlanner.suggestedWake(before: at(9, 0), routineMinutes: 45, bufferMinutes: 10, calendar: utc)
        XCTAssertEqual(wake, at(8, 5))
    }

    func testZeroRoutineIsCommitmentMinusBuffer() {
        let wake = SmartWakePlanner.suggestedWake(before: at(9, 0), routineMinutes: 0, bufferMinutes: 10, calendar: utc)
        XCTAssertEqual(wake, at(8, 50))
    }

    func testNoCommitmentIsNil() {
        XCTAssertNil(SmartWakePlanner.suggestedWake(before: nil, routineMinutes: 30, calendar: utc))
    }

    func testNegativeInputsClampToZeroLead() {
        let wake = SmartWakePlanner.suggestedWake(before: at(7, 0), routineMinutes: -5, bufferMinutes: -5, calendar: utc)
        XCTAssertEqual(wake, at(7, 0))
    }
}
