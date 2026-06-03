import XCTest
@testable import SyncCore

final class ClockTests: XCTestCase {
    func testFixedClockReturnsPinnedInstant() {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = FixedClock(instant)
        XCTAssertEqual(clock.now(), instant)
        // Stable across calls — never reads the wall clock.
        XCTAssertEqual(clock.now(), clock.now())
    }

    func testSystemClockAdvancesMonotonicallyEnough() {
        let clock = SystemClock()
        let first = clock.now()
        let second = clock.now()
        XCTAssertGreaterThanOrEqual(second, first)
    }

    func testMutableClockAdvances() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = MutableClock(start)
        await clock.advance(by: 30)
        let current = await clock.current()
        XCTAssertEqual(current, start.addingTimeInterval(30))

        await clock.set(Date(timeIntervalSince1970: 5_000))
        let reset = await clock.current()
        XCTAssertEqual(reset, Date(timeIntervalSince1970: 5_000))
    }
}
