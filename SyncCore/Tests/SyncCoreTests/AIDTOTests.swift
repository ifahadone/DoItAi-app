import XCTest
@testable import SyncCore

final class AIDTOTests: XCTestCase {
    private func decoder() -> JSONDecoder { JSONCoding.makeDecoder() }

    func testParsedTaskDecodesFromServerShape() throws {
        let json = """
        { "title": "Call the dentist", "start": null, "durationMinutes": null,
          "due": "2026-06-05T09:00:00.000Z", "priority": "p2", "tags": ["health"], "listHint": "Personal" }
        """
        let task = try decoder().decode(AIParsedTask.self, from: Data(json.utf8))
        XCTAssertEqual(task.title, "Call the dentist")
        XCTAssertNil(task.start)
        XCTAssertNotNil(task.due)
        XCTAssertEqual(task.priority, .p2)
        XCTAssertEqual(task.priority.asPriority, .p2)
        XCTAssertEqual(task.tags, ["health"])
        XCTAssertEqual(task.listHint, "Personal")
    }

    func testScheduleProposalDecodes() throws {
        let json = """
        { "blocks": [{ "taskId": "a", "title": "Gym", "startIso": "2026-06-04T09:00:00.000Z",
          "endIso": "2026-06-04T09:30:00.000Z", "reason": "Urgent · earliest open slot" }],
          "unscheduled": [{ "taskId": "b", "title": "Read", "reason": "No free slot" }], "ranked": true }
        """
        let plan = try decoder().decode(AIScheduleProposal.self, from: Data(json.utf8))
        XCTAssertEqual(plan.blocks.count, 1)
        XCTAssertEqual(plan.blocks[0].taskId, "a")
        XCTAssertEqual(plan.unscheduled.count, 1)
        XCTAssertTrue(plan.ranked)
    }

    func testPriorityBridgeRoundTrips() {
        for p in [Priority.none, .p4, .p3, .p2, .p1] {
            XCTAssertEqual(AIPriority(p).asPriority, p)
        }
    }

    func testNarrativeEventParsing() {
        XCTAssertEqual(AINarrativeEvent.parse(dataPayload: #"{"type":"text","delta":"Good morning"}"#), .text("Good morning"))
        XCTAssertEqual(AINarrativeEvent.parse(dataPayload: "[DONE]"), .done)
        if case let .highlights(h)? = AINarrativeEvent.parse(dataPayload: #"{"type":"highlights","highlights":{"taskCount":3,"overdueCount":1}}"#) {
            XCTAssertEqual(h["taskCount"], 3)
            XCTAssertEqual(h["overdueCount"], 1)
        } else {
            XCTFail("expected highlights event")
        }
        XCTAssertNil(AINarrativeEvent.parse(dataPayload: ": keep-alive"))
    }
}
