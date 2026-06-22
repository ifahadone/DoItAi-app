import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The vertical day-planner grid (AppSpec §5.3). Renders hour lines + labels and today's blocks
/// (lane-packed for overlaps via ``DayGridPacker``), with tap-empty-to-create, drag-to-move, and a
/// bottom resize handle. Geometry is the pure ``DayGridLayout``; mutations are surfaced as callbacks
/// so the feature layer owns persistence.
public struct DayGridView: View {
    @Environment(\.theme) private var theme

    private let items: [SectographItem]
    private let titles: [String: String]
    private let busy: [SectographItem]
    private let hourHeight: CGFloat
    private let markerStepMinutes: Int
    private let splitDayAtNoon: Bool
    private let onCreate: ((Int) -> Void)?
    private let onMove: ((String, Int) -> Void)?
    private let onResize: ((String, Int) -> Void)?
    private let onTap: ((String) -> Void)?
    private let onDropSchedule: ((String, Int) -> Void)?
    /// Minute-of-day for the red "now" indicator line (Apple-Calendar style); nil hides it (e.g. when
    /// the grid isn't showing today).
    private let nowMinute: Int?

    @State private var drag: DragState?
    @State private var dropTargeted = false

    private struct DragState: Equatable {
        var id: String
        var deltaMinutes: Int
        var resizing: Bool
    }

    private let gutter: CGFloat = 46

    public init(
        items: [SectographItem],
        titles: [String: String] = [:],
        busy: [SectographItem] = [],
        hourHeight: CGFloat = 56,
        markerStepMinutes: Int = 60,
        splitDayAtNoon: Bool = false,
        onCreate: ((Int) -> Void)? = nil,
        onMove: ((String, Int) -> Void)? = nil,
        onResize: ((String, Int) -> Void)? = nil,
        onTap: ((String) -> Void)? = nil,
        onDropSchedule: ((String, Int) -> Void)? = nil,
        nowMinute: Int? = nil
    ) {
        self.items = items
        self.titles = titles
        self.busy = busy
        self.hourHeight = hourHeight
        self.markerStepMinutes = max(15, markerStepMinutes)
        self.splitDayAtNoon = splitDayAtNoon
        self.onCreate = onCreate
        self.onMove = onMove
        self.onResize = onResize
        self.onTap = onTap
        self.onDropSchedule = onDropSchedule
        self.nowMinute = nowMinute
    }

    public var body: some View {
        if splitDayAtNoon {
            splitDayBody
        } else {
            fullDayBody
        }
    }

    private var fullDayBody: some View {
        let grid = DayGridLayout(hourHeight: hourHeight)
        let lanes = Dictionary(uniqueKeysWithValues: DayGridPacker.assign(items).map { ($0.id, $0) })
        return ScrollView {
            GeometryReader { geo in
                let areaWidth = max(0, geo.size.width - gutter - 8)
                ZStack(alignment: .topLeading) {
                    hourLines(grid: grid, width: geo.size.width)
                    busyBands(grid: grid, width: geo.size.width)
                    Color.clear
                        .frame(width: geo.size.width, height: grid.totalHeight)
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { value in
                            onCreate?(grid.snap(grid.minute(forY: value.location.y)))
                        })
                    ForEach(items) { item in
                        block(item: item, grid: grid,
                              lane: lanes[item.id] ?? LaneAssignment(id: item.id, lane: 0, laneCount: 1),
                              areaWidth: areaWidth)
                    }
                    if let nowMinute {
                        let ny = grid.y(forMinute: max(0, min(1440, nowMinute)))
                        Path { p in
                            p.move(to: CGPoint(x: gutter, y: ny)); p.addLine(to: CGPoint(x: geo.size.width, y: ny))
                        }
                        .stroke(Color.red, lineWidth: 1.5)
                        .allowsHitTesting(false)
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                            .position(x: gutter, y: ny)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geo.size.width, height: grid.totalHeight, alignment: .topLeading)
                .overlay {
                    if dropTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(theme.colors.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .allowsHitTesting(false)
                    }
                }
                .dropDestination(for: String.self) { ids, location in
                    guard let id = ids.first, let onDropSchedule else { return false }
                    onDropSchedule(id, grid.snap(grid.minute(forY: location.y)))
                    return true
                } isTargeted: { dropTargeted = $0 }
            }
            .frame(height: grid.totalHeight)
        }
        .scrollDisabled(drag != nil)
    }

    private var splitDayBody: some View {
        let grid = DayGridLayout(hourHeight: hourHeight, minutesPerDay: 720)
        return ScrollView {
            HStack(alignment: .top, spacing: 0) {
                splitColumn(title: "12a-12p", columnStart: 0, grid: grid)
                splitColumn(title: "12p-12a", columnStart: 720, grid: grid)
            }
            .frame(height: grid.totalHeight + 20, alignment: .top)
        }
        .scrollDisabled(drag != nil)
    }

    private func splitColumn(title: String, columnStart: Int, grid: DayGridLayout) -> some View {
        let columnEnd = columnStart + 720
        let columnItems = items.filter { item in
            let itemEnd = max(item.endMinute, item.startMinute + 1)
            return item.startMinute < columnEnd && itemEnd > columnStart
        }
        let lanes = Dictionary(uniqueKeysWithValues: DayGridPacker.assign(columnItems).map { ($0.id, $0) })
        let columnGutter: CGFloat = 31

        return VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            GeometryReader { geo in
                let areaWidth = max(0, geo.size.width - columnGutter - 6)
                ZStack(alignment: .topLeading) {
                    splitHourLines(grid: grid, width: geo.size.width, columnStart: columnStart, gutter: columnGutter)
                    splitBusyBands(grid: grid, width: geo.size.width, columnStart: columnStart, gutter: columnGutter)
                    Color.clear
                        .frame(width: geo.size.width, height: grid.totalHeight)
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { value in
                            let minute = columnStart + grid.snap(grid.minute(forY: value.location.y))
                            onCreate?(min(1440, minute))
                        })
                    ForEach(columnItems) { item in
                        splitBlock(item: item, grid: grid,
                                   lane: lanes[item.id] ?? LaneAssignment(id: item.id, lane: 0, laneCount: 1),
                                   areaWidth: areaWidth,
                                   columnStart: columnStart,
                                   gutter: columnGutter)
                    }
                    if let nowMinute, nowMinute >= columnStart, nowMinute < columnEnd {
                        let ny = grid.y(forMinute: nowMinute - columnStart)
                        Path { p in
                            p.move(to: CGPoint(x: columnGutter, y: ny)); p.addLine(to: CGPoint(x: geo.size.width, y: ny))
                        }
                        .stroke(Color.red, lineWidth: 1.5)
                        .allowsHitTesting(false)
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                            .position(x: columnGutter, y: ny)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geo.size.width, height: grid.totalHeight, alignment: .topLeading)
                .overlay {
                    if dropTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(theme.colors.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .allowsHitTesting(false)
                    }
                }
                .dropDestination(for: String.self) { ids, location in
                    guard let id = ids.first, let onDropSchedule else { return false }
                    let minute = columnStart + grid.snap(grid.minute(forY: location.y))
                    onDropSchedule(id, min(1440, minute))
                    return true
                } isTargeted: { dropTargeted = $0 }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: grid.totalHeight + 20, alignment: .top)
    }

    /// Calendar free/busy backdrop (P2-5): full-width muted bands behind the task blocks, drawn from
    /// the same `busy:` source the dial uses. Non-interactive — they don't block tap-to-create.
    @ViewBuilder
    private func busyBands(grid: DayGridLayout, width: CGFloat) -> some View {
        ForEach(busy) { band in
            let start = max(0, min(1440, band.startMinute))
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.colors.separator.opacity(0.16))
                .overlay(alignment: .topTrailing) {
                    Text("Busy")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.top, 2)
                }
                .frame(width: max(0, width - gutter - 8),
                       height: grid.height(forDuration: max(15, band.durationMinutes)),
                       alignment: .topLeading)
                .offset(x: gutter + 4, y: grid.y(forMinute: start))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func splitBusyBands(grid: DayGridLayout, width: CGFloat, columnStart: Int, gutter: CGFloat) -> some View {
        ForEach(busy) { band in
            let start = max(0, min(1440, band.startMinute))
            let end = min(1440, max(start + 1, band.endMinute))
            let visibleStart = max(start, columnStart)
            let visibleEnd = min(end, columnStart + 720)
            if visibleEnd > visibleStart {
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.colors.separator.opacity(0.16))
                    .overlay(alignment: .topTrailing) {
                        Text("Busy")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.top, 2)
                    }
                    .frame(width: max(0, width - gutter - 6),
                           height: grid.height(forDuration: visibleEnd - visibleStart),
                           alignment: .topLeading)
                    .offset(x: gutter + 3, y: grid.y(forMinute: visibleStart - columnStart))
                    .allowsHitTesting(false)
            }
        }
    }

    private func hourLines(grid: DayGridLayout, width: CGFloat) -> some View {
        ForEach(Array(stride(from: 0, to: 1440, by: markerStepMinutes)), id: \.self) { minute in
            let y = grid.y(forMinute: minute)
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: CGPoint(x: gutter, y: y)); p.addLine(to: CGPoint(x: width, y: y)) }
                    .stroke(theme.colors.separator.opacity(0.4), lineWidth: 0.5)
                Text(timeLabel(minute))
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(width: gutter - 6, alignment: .trailing)
                    .position(x: (gutter - 6) / 2, y: y)
            }
        }
    }

    private func splitHourLines(grid: DayGridLayout, width: CGFloat, columnStart: Int, gutter: CGFloat) -> some View {
        ForEach(Array(stride(from: columnStart, to: columnStart + 720, by: markerStepMinutes)), id: \.self) { minute in
            let y = grid.y(forMinute: minute - columnStart)
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: CGPoint(x: gutter, y: y)); p.addLine(to: CGPoint(x: width, y: y)) }
                    .stroke(theme.colors.separator.opacity(0.4), lineWidth: 0.5)
                Text(timeLabel(minute))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: gutter - 4, alignment: .trailing)
                    .position(x: (gutter - 4) / 2, y: y)
            }
        }
    }

    private func timeLabel(_ minute: Int) -> String {
        let hour = minute / 60
        let min = minute % 60
        if min != 0 {
            let suffix = hour < 12 ? "a" : "p"
            let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
            return "\(displayHour):\(String(format: "%02d", min))\(suffix)"
        }
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        case let h where h < 12: return "\(h)a"
        default: return "\(hour - 12)p"
        }
    }

    @ViewBuilder
    private func block(item: SectographItem, grid: DayGridLayout, lane: LaneAssignment, areaWidth: CGFloat) -> some View {
        let dragging = drag?.id == item.id
        let moveDelta = dragging && !(drag?.resizing ?? false) ? (drag?.deltaMinutes ?? 0) : 0
        let resizeDelta = dragging && (drag?.resizing ?? false) ? (drag?.deltaMinutes ?? 0) : 0
        let start = max(0, item.startMinute + moveDelta)
        let duration = max(15, item.durationMinutes + resizeDelta)
        let laneWidth = areaWidth / CGFloat(max(1, lane.laneCount))
        let x = gutter + 4 + laneWidth * CGFloat(lane.lane)
        let color = Color(hex: item.colorHex) ?? theme.colors.accent
        let lifted = dragging && !(drag?.resizing ?? false)

        RoundedRectangle(cornerRadius: 8)
            .fill(color.opacity(0.22))
            .overlay(alignment: .topLeading) {
                Text(titles[item.id] ?? "Block")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
                    .lineLimit(2)
                    .padding(.horizontal, 6).padding(.top, 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.5), lineWidth: 1))
            .overlay(alignment: .bottom) { resizeHandle(item: item, grid: grid, color: color) }
            .frame(width: max(0, laneWidth - 4), height: grid.height(forDuration: duration), alignment: .topLeading)
            .scaleEffect(lifted ? 1.03 : 1)
            .shadow(color: .black.opacity(lifted ? 0.18 : 0), radius: lifted ? 6 : 0, x: 0, y: lifted ? 3 : 0)
            .offset(x: x, y: grid.y(forMinute: start))
            .zIndex(lifted ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture { onTap?(item.id) }
            // Drag-to-MOVE is gated behind a long press so a plain vertical swipe is left to the
            // ScrollView (smooth scroll); a press-then-drag picks the block up (Apple Calendar
            // convention). In `.second(true, d)` the press has succeeded — d == nil is the "armed"
            // instant (lift + haptic), a non-nil d is the live drag.
            .gesture(
                LongPressGesture(minimumDuration: 0.25)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        guard case .second(true, let d) = value else { return }
                        if drag?.id != item.id { liftHaptic() } // fires once, on pickup
                        drag = DragState(id: item.id,
                                         deltaMinutes: d.map { minutes($0.translation.height, grid) } ?? 0,
                                         resizing: false)
                    }
                    .onEnded { value in
                        if case .second(true, let d?) = value {
                            onMove?(item.id, grid.snap(item.startMinute + minutes(d.translation.height, grid)))
                        }
                        drag = nil
                    }
            )
            .animation(.easeOut(duration: 0.12), value: lifted)
    }

    @ViewBuilder
    private func splitBlock(
        item: SectographItem,
        grid: DayGridLayout,
        lane: LaneAssignment,
        areaWidth: CGFloat,
        columnStart: Int,
        gutter: CGFloat
    ) -> some View {
        let dragging = drag?.id == item.id
        let moveDelta = dragging && !(drag?.resizing ?? false) ? (drag?.deltaMinutes ?? 0) : 0
        let resizeDelta = dragging && (drag?.resizing ?? false) ? (drag?.deltaMinutes ?? 0) : 0
        let start = max(0, item.startMinute + moveDelta)
        let duration = max(15, item.durationMinutes + resizeDelta)
        let end = min(1440, start + duration)
        let visibleStart = max(start, columnStart)
        let visibleEnd = min(end, columnStart + 720)
        let visibleDuration = max(1, visibleEnd - visibleStart)
        let laneWidth = areaWidth / CGFloat(max(1, lane.laneCount))
        let x = gutter + 3 + laneWidth * CGFloat(lane.lane)
        let color = Color(hex: item.colorHex) ?? theme.colors.accent
        let lifted = dragging && !(drag?.resizing ?? false)

        if visibleEnd > visibleStart {
            RoundedRectangle(cornerRadius: 7)
                .fill(color.opacity(0.22))
                .overlay(alignment: .topLeading) {
                    Text(titles[item.id] ?? "Block")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(color)
                        .lineLimit(2)
                        .padding(.horizontal, 5).padding(.top, 3)
                }
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(color.opacity(0.5), lineWidth: 1))
                .overlay(alignment: .bottom) { resizeHandle(item: item, grid: grid, color: color) }
                .frame(width: max(0, laneWidth - 3),
                       height: grid.height(forDuration: visibleDuration),
                       alignment: .topLeading)
                .scaleEffect(lifted ? 1.03 : 1)
                .shadow(color: .black.opacity(lifted ? 0.18 : 0), radius: lifted ? 6 : 0, x: 0, y: lifted ? 3 : 0)
                .offset(x: x, y: grid.y(forMinute: visibleStart - columnStart))
                .zIndex(lifted ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture { onTap?(item.id) }
                .gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            guard case .second(true, let d) = value else { return }
                            if drag?.id != item.id { liftHaptic() }
                            drag = DragState(id: item.id,
                                             deltaMinutes: d.map { minutes($0.translation.height, grid) } ?? 0,
                                             resizing: false)
                        }
                        .onEnded { value in
                            if case .second(true, let d?) = value {
                                onMove?(item.id, grid.snap(item.startMinute + minutes(d.translation.height, grid)))
                            }
                            drag = nil
                        }
                )
                .animation(.easeOut(duration: 0.12), value: lifted)
        }
    }

    private func resizeHandle(item: SectographItem, grid: DayGridLayout, color: Color) -> some View {
        Capsule().fill(color.opacity(0.6)).frame(width: 28, height: 4).padding(.bottom, 2)
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        drag = DragState(id: item.id, deltaMinutes: minutes(value.translation.height, grid), resizing: true)
                    }
                    .onEnded { value in
                        let newEnd = item.startMinute + max(15, item.durationMinutes + minutes(value.translation.height, grid))
                        onResize?(item.id, grid.snap(newEnd))
                        drag = nil
                    }
            )
    }

    /// A light impact when a block is picked up for moving, so the press-to-move is legible (the move
    /// now requires a brief hold). No-op on platforms without UIKit (e.g. the macOS package build).
    private func liftHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }

    private func minutes(_ points: CGFloat, _ grid: DayGridLayout) -> Int {
        Int((points / hourHeight * 60).rounded())
    }
}
