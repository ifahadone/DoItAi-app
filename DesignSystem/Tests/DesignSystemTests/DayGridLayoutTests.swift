import XCTest
@testable import DesignSystem

final class DayGridLayoutTests: XCTestCase {
    private let grid = DayGridLayout(hourHeight: 60)

    func testMinuteToYAndBack() {
        XCTAssertEqual(grid.y(forMinute: 120), 120, accuracy: 1e-6)
        XCTAssertEqual(grid.y(forMinute: 90), 90, accuracy: 1e-6)
        XCTAssertEqual(grid.minute(forY: 120), 120)
        XCTAssertEqual(grid.totalHeight, 1440, accuracy: 1e-6)
        XCTAssertEqual(grid.height(forDuration: 30), 30, accuracy: 1e-6)
    }

    func testSnap() {
        XCTAssertEqual(grid.snap(67, to: 15), 60)
        XCTAssertEqual(grid.snap(68, to: 15), 75)
        XCTAssertEqual(grid.snap(0, to: 15), 0)
    }

    private func item(_ id: String, _ s: Int, _ e: Int) -> SectographItem {
        SectographItem(id: id, startMinute: s, endMinute: e)
    }

    func testNonOverlappingAllLaneZero() {
        let a = DayGridPacker.assign([item("a", 0, 60), item("b", 60, 120), item("c", 200, 260)])
        XCTAssertTrue(a.allSatisfy { $0.lane == 0 && $0.laneCount == 1 })
    }

    func testTwoOverlappingGetTwoLanes() {
        let a = DayGridPacker.assign([item("a", 0, 90), item("b", 30, 120)])
        let byId = Dictionary(uniqueKeysWithValues: a.map { ($0.id, $0) })
        XCTAssertEqual(Set([byId["a"]!.lane, byId["b"]!.lane]), [0, 1])
        XCTAssertTrue(a.allSatisfy { $0.laneCount == 2 })
    }

    func testClusterThenSeparate() {
        // a,b overlap (cluster of 2); c is separate.
        let a = DayGridPacker.assign([item("a", 0, 60), item("b", 30, 90), item("c", 120, 180)])
        let byId = Dictionary(uniqueKeysWithValues: a.map { ($0.id, $0) })
        XCTAssertEqual(byId["a"]!.laneCount, 2)
        XCTAssertEqual(byId["b"]!.laneCount, 2)
        XCTAssertEqual(byId["c"]!.laneCount, 1)
        XCTAssertEqual(byId["c"]!.lane, 0)
    }

    func testLaneReuseWithinCluster() {
        // a spans the whole window; b and c are inside a but don't overlap each other → both lane 1.
        let a = DayGridPacker.assign([item("a", 0, 120), item("b", 10, 40), item("c", 60, 90)])
        let byId = Dictionary(uniqueKeysWithValues: a.map { ($0.id, $0) })
        XCTAssertEqual(byId["a"]!.lane, 0)
        XCTAssertEqual(byId["b"]!.lane, 1)
        XCTAssertEqual(byId["c"]!.lane, 1)   // reused lane 1 (b already ended)
        XCTAssertTrue(a.allSatisfy { $0.laneCount == 2 })
    }
}
