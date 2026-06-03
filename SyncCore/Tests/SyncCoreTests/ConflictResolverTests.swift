import XCTest
@testable import SyncCore

final class ConflictResolverTests: XCTestCase {
    private let resolver = ConflictResolver()

    private let t0 = Date(timeIntervalSince1970: 1_000) // older
    private let t1 = Date(timeIntervalSince1970: 2_000) // newer

    // MARK: Fast path

    func testFastPathAppliesWhenVersionsMatch() {
        let outcome = resolver.resolveRowLevel(
            clientFields: ["title": .string("A")],
            serverFields: [:],
            clientUpdatedAt: t1,
            serverUpdatedAt: t0,
            clientBaseVersion: 4,
            serverVersion: 4
        )
        XCTAssertEqual(outcome, .applied(mergedFields: ["title": .string("A")], version: 5))
    }

    // MARK: Row-level LWW

    func testRowLevelClientWinsWhenNewer() {
        let outcome = resolver.resolveRowLevel(
            clientFields: ["title": .string("Client")],
            serverFields: ["title": .string("Server")],
            clientUpdatedAt: t1,
            serverUpdatedAt: t0,
            clientBaseVersion: 4,
            serverVersion: 6
        )
        XCTAssertEqual(outcome, .merged(mergedFields: ["title": .string("Client")], serverKept: [], version: 7))
    }

    func testRowLevelServerWinsWhenClientOlder() {
        let outcome = resolver.resolveRowLevel(
            clientFields: ["title": .string("Client")],
            serverFields: ["title": .string("Server")],
            clientUpdatedAt: t0,
            serverUpdatedAt: t1,
            clientBaseVersion: 4,
            serverVersion: 6
        )
        XCTAssertEqual(
            outcome,
            .merged(mergedFields: ["title": .string("Server")], serverKept: ["title"], version: 7)
        )
    }

    func testRowLevelTieGoesToServer() {
        // Equal timestamps: server keeps the field (client win requires strictly newer).
        let outcome = resolver.resolveRowLevel(
            clientFields: ["title": .string("Client")],
            serverFields: ["title": .string("Server")],
            clientUpdatedAt: t1,
            serverUpdatedAt: t1,
            clientBaseVersion: 4,
            serverVersion: 6
        )
        guard case let .merged(_, serverKept, _) = outcome else {
            return XCTFail("expected merged, got \(outcome)")
        }
        XCTAssertEqual(serverKept, ["title"])
    }

    // MARK: Field-level LWW

    func testFieldLevelMixedWinners() {
        // Client edited `title` later than the server, but `notes` earlier → split outcome.
        let outcome = resolver.resolveFieldLevel(
            clientFields: ["title": .string("ClientTitle"), "notes": .string("ClientNotes")],
            serverFields: ["title": .string("ServerTitle"), "notes": .string("ServerNotes")],
            serverFieldMeta: [
                "title": FieldMeta(updatedAt: t0),   // server wrote title earlier → client wins
                "notes": FieldMeta(updatedAt: t1)    // server wrote notes later → server wins
            ],
            clientUpdatedAt: Date(timeIntervalSince1970: 1_500), // between t0 and t1
            clientBaseVersion: 4,
            serverVersion: 6
        )
        guard case let .merged(merged, serverKept, version) = outcome else {
            return XCTFail("expected merged, got \(outcome)")
        }
        XCTAssertEqual(merged["title"], .string("ClientTitle"))
        XCTAssertEqual(merged["notes"], .string("ServerNotes"))
        XCTAssertEqual(serverKept, ["notes"])
        XCTAssertEqual(version, 7)
    }

    func testFieldLevelClientWinsFieldWithNoServerMeta() {
        let outcome = resolver.resolveFieldLevel(
            clientFields: ["rank": .int(9)],
            serverFields: [:],
            serverFieldMeta: [:], // server never touched this field
            clientUpdatedAt: t0,
            clientBaseVersion: 4,
            serverVersion: 6
        )
        guard case let .merged(merged, serverKept, _) = outcome else {
            return XCTFail("expected merged, got \(outcome)")
        }
        XCTAssertEqual(merged["rank"], .int(9))
        XCTAssertTrue(serverKept.isEmpty)
    }

    // MARK: Structural conflicts

    func testUpsertOnDeletedIsStructuralConflict() {
        let outcome = resolver.resolveFieldLevel(
            clientOp: .upsert,
            clientFields: ["title": .string("Resurrect")],
            serverFields: [:],
            serverFieldMeta: [:],
            clientUpdatedAt: t1,
            clientBaseVersion: 4,
            serverVersion: 6,
            serverIsDeleted: true
        )
        XCTAssertEqual(outcome, .structuralConflict(reason: .upsertOnDeleted))
    }

    func testDeleteOnResurrectedIsStructuralConflict() {
        let outcome = resolver.resolveRowLevel(
            clientOp: .delete,
            clientFields: [:],
            serverFields: [:],
            clientUpdatedAt: t0,
            serverUpdatedAt: t1,
            clientBaseVersion: 4,
            serverVersion: 6, // server moved ahead, not deleted
            serverIsDeleted: false
        )
        XCTAssertEqual(outcome, .structuralConflict(reason: .deleteOnResurrected))
    }

    func testDeleteOnAlreadyDeletedIsNotStructuralConflict() {
        // Idempotent delete: server already tombstoned → no structural conflict, fast/merge path.
        let reason = resolver.structuralConflict(
            clientOp: .delete,
            serverIsDeleted: true,
            clientBaseVersion: 4,
            serverVersion: 6
        )
        XCTAssertNil(reason)
    }
}
