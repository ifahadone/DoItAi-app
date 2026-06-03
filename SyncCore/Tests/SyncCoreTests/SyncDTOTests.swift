import XCTest
@testable import SyncCore

/// Verifies the sync envelope DTOs decode from the exact JSON shapes in ApiSpec §6.1–§6.2.
final class SyncDTOTests: XCTestCase {
    private let decoder = JSONCoding.makeDecoder()
    private let encoder = JSONCoding.makeEncoder()

    func testDecodesPushRequestFromApiSpecExample() throws {
        let json = """
        {
          "ops": [
            {
              "opId": "f1e2",
              "entityType": "task",
              "entityId": "a3b4",
              "op": "upsert",
              "baseVersion": 4,
              "clientUpdatedAt": "2026-06-03T08:30:00Z",
              "fields": {
                "title": "Lunch with Sam",
                "scheduledStart": "2026-06-04T13:00:00Z",
                "scheduledEnd": "2026-06-04T14:00:00Z",
                "status": 1
              }
            }
          ]
        }
        """
        let request = try decoder.decode(SyncPushRequest.self, from: Data(json.utf8))
        XCTAssertEqual(request.ops.count, 1)
        let op = request.ops[0]
        XCTAssertEqual(op.opId, "f1e2")
        XCTAssertEqual(op.entityType, .task)
        XCTAssertEqual(op.op, .upsert)
        XCTAssertEqual(op.baseVersion, 4)
        XCTAssertEqual(op.fields["status"], .int(1))
        XCTAssertEqual(op.fields["title"], .string("Lunch with Sam"))
    }

    func testDecodesPushResponseFromApiSpecExample() throws {
        let json = """
        {
          "results": [
            {
              "opId": "f1e2",
              "entityId": "a3b4",
              "status": "applied",
              "serverVersion": 5,
              "serverFields": null,
              "committedSeq": "91432"
            }
          ]
        }
        """
        let response = try decoder.decode(SyncPushResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.results.first?.status, .applied)
        XCTAssertEqual(response.results.first?.serverVersion, 5)
        XCTAssertEqual(response.results.first?.committedSeq, "91432")
        XCTAssertNil(response.results.first?.serverFields)
    }

    func testDecodesMergedResultWithServerFields() throws {
        // ApiSpec §21 "Sync conflict (merged) example".
        let json = """
        { "opId":"f1e2","entityId":"a3b4","status":"merged","serverVersion":9,
          "serverFields":{ "title":"Lunch with Samir" }, "committedSeq":"91710" }
        """
        let result = try decoder.decode(SyncPushResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.status, .merged)
        XCTAssertEqual(result.serverFields?["title"], .string("Lunch with Samir"))
    }

    func testDecodesPullResponseFromApiSpecExample() throws {
        let json = """
        {
          "changes": [
            { "entityType": "task", "entityId": "a3b4", "op": "upsert", "version": 5,
              "payload": { "id": "a3b4", "title": "x" }, "seq": "91432" },
            { "entityType": "task", "entityId": "9c10", "op": "delete", "version": 3, "seq": "91440" }
          ],
          "nextCursor": "kFnAkQ==",
          "hasMore": false
        }
        """
        let response = try decoder.decode(SyncPullResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.changes.count, 2)
        XCTAssertEqual(response.nextCursor, "kFnAkQ==")
        XCTAssertFalse(response.hasMore)
        XCTAssertEqual(response.changes[0].op, .upsert)
        XCTAssertNotNil(response.changes[0].payload)
        XCTAssertEqual(response.changes[1].op, .delete)
        XCTAssertNil(response.changes[1].payload) // tombstone has no payload
    }

    func testOutboxOpProjectsToPushOpDroppingBookkeeping() throws {
        let op = OutboxOp(
            opId: "op-1",
            entityType: .task,
            entityId: "task-1",
            op: .upsert,
            baseVersion: 0,
            clientUpdatedAt: Date(timeIntervalSince1970: 1_000),
            fields: ["title": .string("New")],
            attemptCount: 3,
            enqueuedAt: Date(timeIntervalSince1970: 900)
        )
        let push = op.toPushOp()
        XCTAssertEqual(push.opId, "op-1")
        XCTAssertEqual(push.entityId, "task-1")
        XCTAssertEqual(push.fields["title"], .string("New"))

        // Durable op itself still round-trips (it's persisted locally).
        let decoded = try decoder.decode(OutboxOp.self, from: try encoder.encode(op))
        XCTAssertEqual(decoded, op)
    }
}
