import SwiftUI

/// The sectograph — DoIT's 24-hour radial day-dial (AppSpec §5.3). Renders today's blocks as arcs on a
/// faint full-day track, with hour ticks, cardinal labels, and a live now-hand. All geometry comes from
/// the pure ``SectographLayout`` (unit-tested); this view is just the Canvas + a `TimelineView` clock,
/// so the same core also drives the widgets and Live Activity.
public struct SectographView: View {
    @Environment(\.theme) private var theme

    private let items: [SectographItem]
    private let ringWidth: CGFloat
    private let showNowHand: Bool

    public init(items: [SectographItem], ringWidth: CGFloat = 24, showNowHand: Bool = true) {
        self.items = items
        self.ringWidth = ringWidth
        self.showNowHand = showNowHand
    }

    public var body: some View {
        GeometryReader { geo in
            let layout = SectographLayout(size: geo.size, ringWidth: ringWidth)
            ZStack {
                Canvas { context, _ in
                    drawTrack(context, layout)
                    drawHourTicks(context, layout)
                    drawArcs(context, layout)
                }
                cardinalLabels(layout)
                if showNowHand {
                    TimelineView(.periodic(from: .now, by: 60)) { tick in
                        nowHand(layout, date: tick.date)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Day dial")
        .accessibilityValue("\(items.count) scheduled blocks")
    }

    private var midRadius: (SectographLayout) -> CGFloat { { ($0.innerRadius + $0.outerRadius) / 2 } }

    private func drawTrack(_ context: GraphicsContext, _ layout: SectographLayout) {
        let path = Path { p in
            p.addArc(center: layout.center, radius: midRadius(layout),
                     startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        }
        context.stroke(path, with: .color(theme.colors.separator.opacity(0.4)), lineWidth: ringWidth)
    }

    private func drawHourTicks(_ context: GraphicsContext, _ layout: SectographLayout) {
        for hour in 0..<24 {
            let minute = hour * 60
            let isMajor = hour % 6 == 0
            let outer = layout.point(forMinute: minute, radius: layout.outerRadius)
            let inner = layout.point(forMinute: minute, radius: layout.outerRadius - (isMajor ? ringWidth : ringWidth / 2))
            let path = Path { p in p.move(to: inner); p.addLine(to: outer) }
            context.stroke(path, with: .color(theme.colors.separator.opacity(isMajor ? 0.8 : 0.4)),
                           lineWidth: isMajor ? 1.5 : 0.75)
        }
    }

    private func drawArcs(_ context: GraphicsContext, _ layout: SectographLayout) {
        for arc in layout.arcs(for: items) {
            // Non-wrapping blocks only sweep forward; a wrapping block is split visually by drawing the
            // forward sweep (start→end the short way is handled by SwiftUI when start<end).
            let path = Path { p in
                p.addArc(center: layout.center, radius: midRadius(layout),
                         startAngle: .radians(arc.startAngle), endAngle: .radians(max(arc.endAngle, arc.startAngle + 0.01)),
                         clockwise: false)
            }
            let color = Color(hex: arc.colorHex) ?? theme.colors.accent
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: ringWidth - 6, lineCap: .round))
        }
    }

    @ViewBuilder
    private func cardinalLabels(_ layout: SectographLayout) -> some View {
        ForEach([(0, "12a"), (360, "6a"), (720, "12p"), (1080, "6p")], id: \.0) { minute, label in
            let pos = layout.point(forMinute: minute, radius: layout.innerRadius - 14)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .position(pos)
        }
    }

    private func nowHand(_ layout: SectographLayout, date: Date) -> some View {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let tip = layout.point(forMinute: minute, radius: layout.outerRadius)
        return ZStack {
            Path { p in p.move(to: layout.center); p.addLine(to: tip) }
                .stroke(theme.colors.statusOverdue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            Circle().fill(theme.colors.statusOverdue).frame(width: 7, height: 7).position(layout.center)
        }
    }
}
