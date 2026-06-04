import XCTest
@testable import SyncCore

final class GeofencePlannerTests: XCTestCase {
    private func reminder(_ id: String, lat: Double, lon: Double) -> LocationReminder {
        LocationReminder(id: id, region: ReminderRegion(center: GeoPoint(lat: lat, lon: lon), radius: 100))
    }

    func testUnderCapKeepsAll() {
        let rs = (0..<5).map { reminder("r\($0)", lat: Double($0), lon: 0) }
        let kept = GeofencePlanner.plan(reminders: rs, userLocation: nil, cap: 20)
        XCTAssertEqual(kept.count, 5)
        XCTAssertEqual(kept.map(\.id), rs.map(\.id))
    }

    func testOverCapWithoutLocationKeepsStablePrefix() {
        let rs = (0..<25).map { reminder("r\($0)", lat: Double($0), lon: 0) }
        let kept = GeofencePlanner.plan(reminders: rs, userLocation: nil, cap: 20)
        XCTAssertEqual(kept.count, 20)
        XCTAssertEqual(kept.map(\.id), (0..<20).map { "r\($0)" })
    }

    func testOverCapKeepsNearest() {
        // 25 reminders marching north; user sits at the far (north) end → nearest are the high indices.
        let rs = (0..<25).map { reminder("r\($0)", lat: Double($0), lon: 0) }
        let user = GeoPoint(lat: 24, lon: 0)
        let kept = GeofencePlanner.plan(reminders: rs, userLocation: user, cap: 20)
        XCTAssertEqual(kept.count, 20)
        let keptIds = Set(kept.map(\.id))
        XCTAssertTrue(keptIds.contains("r24"))           // closest kept
        XCTAssertTrue(keptIds.contains("r5"))            // 20th-closest kept
        XCTAssertFalse(keptIds.contains("r4"))           // 21st-closest dropped
        XCTAssertFalse(keptIds.contains("r0"))           // farthest dropped
    }

    func testDistanceMonotonic() {
        let origin = GeoPoint(lat: 0, lon: 0)
        let near = GeoPoint(lat: 0, lon: 0.01)
        let far = GeoPoint(lat: 0, lon: 0.5)
        XCTAssertLessThan(
            GeofencePlanner.distanceMeters(from: origin, to: near),
            GeofencePlanner.distanceMeters(from: origin, to: far)
        )
        // ~1.11 km per 0.01° longitude at the equator; sanity-check the magnitude.
        let d = GeofencePlanner.distanceMeters(from: origin, to: near)
        XCTAssertEqual(d, 1113, accuracy: 50)
    }
}
