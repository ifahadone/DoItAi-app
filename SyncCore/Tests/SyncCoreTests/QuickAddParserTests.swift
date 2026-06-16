import XCTest
@testable import SyncCore

final class QuickAddParserTests: XCTestCase {
    func testPlainTitle() {
        let r = QuickAddParser.parse("Buy milk")
        XCTAssertEqual(r.title, "Buy milk")
        XCTAssertNil(r.dueAt)
        XCTAssertTrue(r.tagNames.isEmpty)
        XCTAssertEqual(r.priority, .none)
    }

    func testTagsAndPriorityStrippedFromTitle() {
        let r = QuickAddParser.parse("Submit the report #urgent #work !2")
        XCTAssertEqual(r.title, "Submit the report")
        XCTAssertEqual(r.tagNames, ["urgent", "work"])    // input order preserved
        XCTAssertEqual(r.priority, .p2)                    // !2 → 5-2 = 3 = p2
    }

    func testPriorityP1Variants() {
        XCTAssertEqual(QuickAddParser.parse("Call mom !p1").priority, .p1)
        XCTAssertEqual(QuickAddParser.parse("Call mom !1").priority, .p1)
        XCTAssertEqual(QuickAddParser.parse("Call mom !4").priority, .p4)
    }

    func testAbsoluteDateParsedAndStripped() {
        // Absolute date ⇒ deterministic regardless of "now".
        let r = QuickAddParser.parse("Team meeting March 15 2027 at 3pm #work")
        XCTAssertEqual(r.tagNames, ["work"])
        XCTAssertNotNil(r.dueAt)
        if let due = r.dueAt {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            let c = cal.dateComponents([.year, .month, .day, .hour], from: due)
            XCTAssertEqual(c.year, 2027)
            XCTAssertEqual(c.month, 3)
            XCTAssertEqual(c.day, 15)
            XCTAssertEqual(c.hour, 15)
        }
        // The date phrase is removed from the title (allowing for "at" left behind is fine to assert loosely).
        XCTAssertTrue(r.title.contains("Team meeting"))
        XCTAssertFalse(r.title.contains("2027"))
    }

    func testRelativeDateProducesADate() {
        let r = QuickAddParser.parse("Lunch with Sam tomorrow 1pm #work !p1")
        XCTAssertEqual(r.tagNames, ["work"])
        XCTAssertEqual(r.priority, .p1)
        XCTAssertNotNil(r.dueAt)                  // relative date resolves off the system clock
        XCTAssertEqual(r.title, "Lunch with Sam") // tokens + date phrase stripped
    }

    // MARK: - FR-QADD-090: duration -> estimatedMinutes

    func testDurationHoursParsed() {
        let r = QuickAddParser.parse("Design review 1h")
        XCTAssertEqual(r.title, "Design review")
        XCTAssertEqual(r.estimatedMinutes, 60)
    }

    func testDurationHoursAndMinutes() {
        XCTAssertEqual(QuickAddParser.parse("Workshop 1h30m").estimatedMinutes, 90)
        XCTAssertEqual(QuickAddParser.parse("Standup for 15 min").estimatedMinutes, 15)
        XCTAssertEqual(QuickAddParser.parse("Deep work 2 hours").estimatedMinutes, 120)
    }

    func testDurationMinutesOnly() {
        let r = QuickAddParser.parse("Call Sam 30m")
        XCTAssertEqual(r.title, "Call Sam")
        XCTAssertEqual(r.estimatedMinutes, 30)
    }

    func testNoDurationIsNil() {
        XCTAssertNil(QuickAddParser.parse("Buy milk").estimatedMinutes)
    }
}
