import CoreGraphics
import Foundation

// The vertical day-planner grid (AppSpec §5.3 "day planner"). Pure geometry + overlap lane-packing,
// reusing ``SectographItem`` (minutes-into-day) so the dial and the grid share one block model. No
// SwiftUI — unit-tested. Blocks here are single-day `[start, end)`; midnight-wrapping isn't modeled in
// the grid (a wrapped block is clamped to the day's end by the view).

public struct DayGridLayout: Equatable, Sendable {
    /// Points per hour (vertical scale).
    public var hourHeight: CGFloat
    public var minutesPerDay: Int

    public init(hourHeight: CGFloat = 56, minutesPerDay: Int = 1440) {
        self.hourHeight = hourHeight
        self.minutesPerDay = max(1, minutesPerDay)
    }

    public var totalHeight: CGFloat { CGFloat(minutesPerDay) / 60 * hourHeight }

    public func y(forMinute minute: Int) -> CGFloat { CGFloat(minute) / 60 * hourHeight }

    public func height(forDuration minutes: Int) -> CGFloat { CGFloat(max(1, minutes)) / 60 * hourHeight }

    public func minute(forY y: CGFloat) -> Int {
        let minute = Int((y / hourHeight * 60).rounded())
        return min(max(0, minute), minutesPerDay)
    }

    /// Snap a minute to the nearest `step` (e.g. 15) — used when dragging/placing a block.
    public func snap(_ minute: Int, to step: Int = 15) -> Int {
        guard step > 0 else { return minute }
        let snapped = ((minute + step / 2) / step) * step
        return min(max(0, snapped), minutesPerDay)
    }
}

/// Which horizontal lane a block occupies, and how many lanes its overlap cluster spans (so all blocks
/// in a cluster render at equal widths).
public struct LaneAssignment: Equatable, Sendable, Identifiable {
    public var id: String
    public var lane: Int
    public var laneCount: Int

    public init(id: String, lane: Int, laneCount: Int) {
        self.id = id
        self.lane = lane
        self.laneCount = laneCount
    }
}

public enum DayGridPacker {
    /// Greedy interval-graph coloring: overlapping blocks get distinct side-by-side lanes; within each
    /// maximal overlap cluster every block reports the cluster's lane count (equal widths). Order is by
    /// start, then end.
    public static func assign(_ items: [SectographItem]) -> [LaneAssignment] {
        let sorted = items.sorted {
            $0.startMinute != $1.startMinute ? $0.startMinute < $1.startMinute : $0.endMinute < $1.endMinute
        }
        func end(_ item: SectographItem) -> Int {
            item.endMinute > item.startMinute ? item.endMinute : item.startMinute + 1
        }

        // First-fit lane assignment.
        var laneEnds: [Int] = []
        var lane: [String: Int] = [:]
        for item in sorted {
            if let index = laneEnds.firstIndex(where: { $0 <= item.startMinute }) {
                laneEnds[index] = end(item)
                lane[item.id] = index
            } else {
                lane[item.id] = laneEnds.count
                laneEnds.append(end(item))
            }
        }

        // Cluster sweep → shared lane count.
        var laneCount: [String: Int] = [:]
        var cluster: [SectographItem] = []
        var clusterEnd = Int.min
        func flush() {
            guard !cluster.isEmpty else { return }
            let count = (cluster.compactMap { lane[$0.id] }.max() ?? 0) + 1
            for member in cluster { laneCount[member.id] = count }
            cluster.removeAll()
            clusterEnd = Int.min
        }
        for item in sorted {
            if cluster.isEmpty || item.startMinute < clusterEnd {
                cluster.append(item)
                clusterEnd = max(clusterEnd, end(item))
            } else {
                flush()
                cluster.append(item)
                clusterEnd = end(item)
            }
        }
        flush()

        return sorted.map { LaneAssignment(id: $0.id, lane: lane[$0.id] ?? 0, laneCount: laneCount[$0.id] ?? 1) }
    }
}
