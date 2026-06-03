import XCTest
@testable import SyncCore

final class AnyCodableTests: XCTestCase {
    private func roundTrip(_ value: AnyCodable) throws -> AnyCodable {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(AnyCodable.self, from: data)
    }

    func testScalarsRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.string("hi")), .string("hi"))
        XCTAssertEqual(try roundTrip(.int(42)), .int(42))
        XCTAssertEqual(try roundTrip(.bool(true)), .bool(true))
        XCTAssertEqual(try roundTrip(.null), .null)
    }

    func testIntegerDoesNotBecomeDouble() throws {
        // status: 1 must stay an int, not 1.0 — important for the integer-backed enums on the wire.
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: Data("1".utf8))
        XCTAssertEqual(decoded, .int(1))
    }

    func testDoublePreserved() throws {
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: Data("1.5".utf8))
        XCTAssertEqual(decoded, .double(1.5))
    }

    func testNestedContainersRoundTrip() throws {
        let value = AnyCodable.object([
            "title": .string("Lunch"),
            "status": .int(1),
            "tagIds": .array([.string("a"), .string("b")]),
            "nested": .object(["k": .bool(false)]),
            "missing": .null
        ])
        XCTAssertEqual(try roundTrip(value), value)
    }

    func testFieldBagDecodesFromRealisticPatchJSON() throws {
        // Mirrors the ApiSpec §6.1 push "fields" patch.
        let json = """
        { "title": "Lunch with Sam", "scheduledStart": "2026-06-04T13:00:00Z", "status": 1, "archived": false }
        """
        let bag = try JSONDecoder().decode([String: AnyCodable].self, from: Data(json.utf8))
        XCTAssertEqual(bag["title"], .string("Lunch with Sam"))
        XCTAssertEqual(bag["status"], .int(1))
        XCTAssertEqual(bag["archived"], .bool(false))
        XCTAssertEqual(bag["scheduledStart"], .string("2026-06-04T13:00:00Z"))
    }

    func testWrapSupportedTypes() {
        XCTAssertEqual(AnyCodable.wrap(nil), .null)
        XCTAssertEqual(AnyCodable.wrap(7), .int(7))
        XCTAssertEqual(AnyCodable.wrap(true), .bool(true))
        XCTAssertEqual(AnyCodable.wrap("x"), .string("x"))
        XCTAssertEqual(AnyCodable.wrap([1, 2]), .array([.int(1), .int(2)]))
    }
}
