import SwiftUI

/// The vertical day-planner grid (AppSpec §5.3). Renders hour lines + labels and today's blocks
/// (lane-packed for overlaps via ``DayGridPacker``), with tap-empty-to-create, drag-to-move, and a
/// bottom resize handle. Geometry is the pure ``DayGridLayout``; mutations are surfaced as callbacks
/// so the feature layer owns persistence.
public struct DayGridView: View {
    @Environment(\.theme) private var theme

    private let items: [SectographItem]
    private let titles: [String: String]
    private let hourHeight: CGFloat
    private let onCreate: ((Int) -> Void)?
    private let onMove: ((String, Int) -> Void)?
    private let onResize: ((String, Int) -> Void)?
    private let onTap: ((String) -> Void)?

    @State private var drag: DragState?

    private struct DragState: Equatable {
        var id: String
        var deltaMinutes: Int
        var resizing: Bool
    }

    private let gutter: CGFloat = 46

    public init(
        items: [SectographItem],
        titles: [String: String] = [:],
        hourHeight: CGFloat = 56,
        onCreate: ((Int) -> Void)? = nil,
        onMove: ((String, Int) -> Void)? = nil,
        onResize: ((String, Int) -> Void)? = nil,
        onTap: ((String) -> Void)? = nil
    ) {
        self.items = items
        self.titles = titles
        self.hourHeight = hourHeight
        self.onCreate = onCreate
        self.onMove = onMove
        self.onResize = onResize
        self.onTap = onTap
    }

    public var body: some View {
        let grid = DayGridLayout(hourHeight: hourHeight)
        let lanes = Dictionary(uniqueKeysWithValues: DayGridPacker.assign(items).map { ($0.id, $0) })
        ScrollView {
            GeometryReader { geo in
                let areaWidth = max(0, geo.size.width - gutter - 8)
                ZStack(alignment: .topLeading) {
                    hourLines(grid: grid, width: geo.size.width)
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
                }
                .frame(width: geo.size.width, height: grid.totalHeight, alignment: .topLeading)
            }
            .frame(height: grid.totalHeight)
        }
    }

    private func hourLines(grid: DayGridLayout, width: CGFloat) -> some View {
        ForEach(0..<24, id: \.self) { hour in
            let y = grid.y(forMinute: hour * 60)
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: CGPoint(x: gutter, y: y)); p.addLine(to: CGPoint(x: width, y: y)) }
                    .stroke(theme.colors.separator.opacity(0.4), lineWidth: 0.5)
                Text(hourLabel(hour))
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(width: gutter - 6, alignment: .trailing)
                    .position(x: (gutter - 6) / 2, y: y)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
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
            .offset(x: x, y: grid.y(forMinute: start))
            .onTapGesture { onTap?(item.id) }
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        drag = DragState(id: item.id, deltaMinutes: minutes(value.translation.height, grid), resizing: false)
                    }
                    .onEnded { value in
                        onMove?(item.id, grid.snap(item.startMinute + minutes(value.translation.height, grid)))
                        drag = nil
                    }
            )
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

    private func minutes(_ points: CGFloat, _ grid: DayGridLayout) -> Int {
        Int((points / hourHeight * 60).rounded())
    }
}
