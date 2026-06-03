import CoreGraphics
import Foundation

// The sectograph is DoIT's signature 24-hour radial day-dial (AppSpec §5.3). `SectographLayout` is its
// PURE geometry core — no SwiftUI — so the math is unit/snapshot-tested once and reused by the view,
// the home/lock widgets, and the Live Activity. Minutes run 0…1440 (midnight…midnight); midnight sits
// at the top (12 o'clock) and time advances CLOCKWISE. Angles are radians in screen space (y-down,
// measured from the +x axis), so 12 o'clock = -π/2.

/// A scheduled span to draw on the dial (e.g. a task's scheduled block).
public struct SectographItem: Identifiable, Equatable, Sendable {
    public var id: String
    /// Minutes into the day, 0…1440. A block that wraps midnight has `endMinute < startMinute`.
    public var startMinute: Int
    public var endMinute: Int
    public var colorHex: String?

    public init(id: String, startMinute: Int, endMinute: Int, colorHex: String? = nil) {
        self.id = id
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.colorHex = colorHex
    }

    /// Duration in minutes, accounting for a midnight wrap.
    public var durationMinutes: Int {
        endMinute >= startMinute ? endMinute - startMinute : (1440 - startMinute) + endMinute
    }
}

/// A resolved arc ready to stroke (angles in radians; radii in points).
public struct ArcDescriptor: Identifiable, Equatable, Sendable {
    public var id: String
    public var startAngle: Double
    public var endAngle: Double
    public var innerRadius: CGFloat
    public var outerRadius: CGFloat
    public var colorHex: String?

    public init(id: String, startAngle: Double, endAngle: Double,
                innerRadius: CGFloat, outerRadius: CGFloat, colorHex: String?) {
        self.id = id
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.colorHex = colorHex
    }
}

public struct SectographLayout: Equatable, Sendable {
    public var size: CGSize
    /// Thickness of the arc band.
    public var ringWidth: CGFloat
    public var minutesPerDay: Int

    public init(size: CGSize, ringWidth: CGFloat = 22, minutesPerDay: Int = 1440) {
        self.size = size
        self.ringWidth = ringWidth
        self.minutesPerDay = max(1, minutesPerDay)
    }

    public var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    public var outerRadius: CGFloat { max(0, min(size.width, size.height) / 2) }
    public var innerRadius: CGFloat { max(0, outerRadius - ringWidth) }

    // MARK: - Angle ↔ minute

    /// The render angle (radians) for a minute. Midnight (0) is at the top; time advances clockwise.
    public func angle(forMinute minute: Int) -> Double {
        let fraction = Double(minute) / Double(minutesPerDay)
        return -Double.pi / 2 + fraction * 2 * .pi
    }

    /// Inverse of ``angle(forMinute:)`` — the minute (0…<minutesPerDay) for a render angle.
    public func minute(forAngle angle: Double) -> Int {
        var shifted = (angle + Double.pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
        if shifted < 0 { shifted += 2 * .pi }
        let minute = Int((shifted / (2 * .pi) * Double(minutesPerDay)).rounded())
        return ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }

    /// A point on the dial for a minute at a given radius.
    public func point(forMinute minute: Int, radius: CGFloat) -> CGPoint {
        let a = angle(forMinute: minute)
        return CGPoint(x: center.x + radius * CGFloat(cos(a)),
                       y: center.y + radius * CGFloat(sin(a)))
    }

    // MARK: - Items → arcs

    public func arcs(for items: [SectographItem]) -> [ArcDescriptor] {
        items.map { item in
            // Guarantee a sliver of visible sweep even for zero/short blocks.
            let endMinute = item.durationMinutes <= 0 ? item.startMinute + 1 : item.endMinute
            return ArcDescriptor(
                id: item.id,
                startAngle: angle(forMinute: item.startMinute),
                endAngle: angle(forMinute: endMinute),
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                colorHex: item.colorHex
            )
        }
    }

    // MARK: - Hit-testing

    /// The minute the point's angle maps to (radius-independent) — for scrubbing/placing a block.
    public func time(at point: CGPoint) -> Int {
        let angle = atan2(Double(point.y - center.y), Double(point.x - center.x))
        return minute(forAngle: angle)
    }

    /// Whether a point falls within the dial's arc band.
    public func ringContains(_ point: CGPoint) -> Bool {
        let dx = Double(point.x - center.x), dy = Double(point.y - center.y)
        let distance = CGFloat((dx * dx + dy * dy).squareRoot())
        return distance >= innerRadius && distance <= outerRadius
    }

    /// The item under a point: it must be within the ring band and the item's angular span (the first
    /// match wins for overlaps). Returns `nil` if the point misses the band or no item covers that time.
    public func hitTest(at point: CGPoint, items: [SectographItem]) -> SectographItem.ID? {
        guard ringContains(point) else { return nil }
        let minute = time(at: point)
        return items.first { item in
            if item.endMinute >= item.startMinute {
                return minute >= item.startMinute && minute < item.endMinute
            } else { // wraps midnight
                return minute >= item.startMinute || minute < item.endMinute
            }
        }?.id
    }
}
