import SwiftUI

/// The user-selectable day-dial styles (AppSpec §5.3). `aurora` is the rich gradient dial; the others
/// are the cleaner "sector" family. Persisted as a raw string in `@AppStorage("dialStyle")`.
public enum DialStyle: String, CaseIterable, Identifiable, Sendable {
    case halo
    case aurora
    case donut
    case iconClock
    case classic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .halo: return "Halo"
        case .aurora: return "Aurora"
        case .donut: return "Donut"
        case .iconClock: return "Icon Clock"
        case .classic: return "Sectograph Classic"
        }
    }

    public var blurb: String {
        switch self {
        case .halo: return "Now & next in focus, glowing time bead"
        case .aurora: return "Gradient arcs, twilight backdrop, glow"
        case .donut: return "Flat wedges + 24-hour numbers"
        case .iconClock: return "Color wedges with icons + analog hub"
        case .classic: return "12-hour clock face, radial titles, rim times"
        }
    }
}

/// Renders the day-dial in the chosen ``DialStyle``. All styles share the pure ``SectographLayout``
/// geometry; only the drawing differs. Drop-in for the Today hero and the gallery.
public struct SectographDial: View {
    @Environment(\.theme) private var theme

    private let items: [SectographItem]
    private let busy: [SectographItem]
    private let labels: [String: String]
    private let titles: [String: String]
    private let style: DialStyle
    private let ringWidth: CGFloat
    private let showNowHand: Bool
    private let backed: Bool

    public init(items: [SectographItem], busy: [SectographItem] = [], labels: [String: String] = [:],
                titles: [String: String] = [:], style: DialStyle = .aurora,
                ringWidth: CGFloat = 24, showNowHand: Bool = true, backed: Bool = true) {
        self.items = items
        self.busy = busy
        self.labels = labels
        self.titles = titles
        self.style = style
        self.ringWidth = ringWidth
        self.showNowHand = showNowHand
        self.backed = backed
    }

    public var body: some View {
        if backed {
            ZStack {
                // A subtle raised "face" so the dial reads as a defined object on any background
                // (the faint clock face / track otherwise washes out on a plain page).
                Circle()
                    .fill(theme.colors.background)
                    .overlay(Circle().strokeBorder(theme.colors.separator.opacity(0.6), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 3)
                styleContent.padding(12)
            }
            .aspectRatio(1, contentMode: .fit) // keep the backing a circle, not an ellipse
        } else {
            styleContent
        }
    }

    @ViewBuilder
    private var styleContent: some View {
        switch style {
        case .halo:
            HaloDial(items: items, titles: titles)
        case .aurora:
            SectographView(items: items, busy: busy, labels: labels, titles: titles,
                           ringWidth: ringWidth, showNowHand: showNowHand)
        case .donut:
            DonutDial(items: items, titles: titles, showNowHand: showNowHand)
        case .iconClock:
            IconClockDial(items: items, titles: titles)
        case .classic:
            ClassicDial(items: items, titles: titles)
        }
    }
}

// MARK: - Shared geometry helpers (pure, file-scoped)

/// A filled annular sector (donut wedge) for a block, with optional angular padding (gaps).
func annularWedge(_ layout: SectographLayout, _ startMin: Int, _ endMin: Int,
                  inner: CGFloat, outer: CGFloat, padDeg: Double = 0) -> Path {
    let pad = padDeg * .pi / 180
    let start = layout.angle(forMinute: startMin) + pad
    var end = layout.angle(forMinute: endMin) - pad
    if endMin <= startMin { end += 2 * .pi }
    if end <= start { end = start + 0.001 }
    return Path { p in
        p.addArc(center: layout.center, radius: outer, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        p.addArc(center: layout.center, radius: inner, startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
        p.closeSubpath()
    }
}

func dialMinuteOfDay(_ date: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

func pointAt(_ center: CGPoint, _ angle: Double, _ radius: CGFloat) -> CGPoint {
    CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
}

private func hhmm(_ minute: Int) -> String { String(format: "%d:%02d", minute / 60, minute % 60) }

private func instantDot(_ ctx: GraphicsContext, _ layout: SectographLayout, _ item: SectographItem, radius: CGFloat) {
    let p = layout.point(forMinute: item.startMinute, radius: radius)
    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
             with: .color(Color(hex: item.colorHex) ?? .red))
}

// MARK: - Donut

struct DonutDial: View {
    let items: [SectographItem]
    let titles: [String: String]
    var showNowHand: Bool = true

    var body: some View {
        GeometryReader { geo in
            let layout = SectographLayout(size: geo.size, ringWidth: 1)
            let r = layout.outerRadius, inner = r * 0.52, outer = r * 0.88
            TimelineView(.periodic(from: .now, by: 60)) { tick in
                let now = dialMinuteOfDay(tick.date)
                ZStack {
                    Canvas { ctx, _ in
                        ctx.fill(annularWedge(layout, 0, 1439, inner: inner, outer: outer), with: .color(.gray.opacity(0.08)))
                        for item in items where !item.isInstant {
                            let emph = item.isEmphasized || layout.contains(minute: now, item)
                            let base = Color(hex: item.colorHex) ?? .blue
                            ctx.fill(annularWedge(layout, item.startMinute, item.endMinute, inner: inner, outer: emph ? outer + 3 : outer),
                                     with: .color(base.opacity(item.isDone ? 0.3 : (emph ? 1 : 0.82))))
                        }
                        for item in items where item.isInstant { instantDot(ctx, layout, item, radius: (inner + outer) / 2) }
                        for hour in stride(from: 0, to: 24, by: 3) {
                            let p = layout.point(forMinute: hour * 60, radius: r * 0.96)
                            var t = ctx.resolve(Text("\(hour)").font(.system(size: max(7, r * 0.06), weight: .medium)))
                            t.shading = .color(.secondary)
                            ctx.draw(t, at: p, anchor: .center)
                        }
                        if showNowHand {
                            let tip = layout.point(forMinute: now, radius: outer)
                            ctx.stroke(Path { $0.move(to: layout.center); $0.addLine(to: tip) },
                                       with: .color(.red), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        }
                    }
                    centerClockText(tick.date, holeRadius: inner)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Day dial, \(items.count) blocks")
    }
}

// MARK: - Icon Clock (the polished wedge dial)

struct IconClockDial: View {
    let items: [SectographItem]
    let titles: [String: String]

    var body: some View {
        GeometryReader { geo in
            let layout = SectographLayout(size: geo.size, ringWidth: 1)
            let r = layout.outerRadius
            let inner = r * 0.46, outer = r * 0.80, rimR = r * 0.93, hubR = r * 0.38
            TimelineView(.periodic(from: .now, by: 60)) { tick in
                ZStack {
                    Canvas { ctx, _ in
                        // Bold color wedges with white gaps.
                        for item in items {
                            let base = Color(hex: item.colorHex) ?? .blue
                            let wedge = annularWedge(layout, item.startMinute, item.endMinute,
                                                     inner: inner, outer: outer, padDeg: 3)
                            ctx.fill(wedge, with: .color(base.opacity(item.isDone ? 0.4 : 1)))
                        }
                        // Start-time labels on the rim, tangent to the curve.
                        for item in items where item.durationMinutes >= 30 {
                            let angle = layout.angle(forMinute: item.startMinute)
                            let p = layout.point(forMinute: item.startMinute, radius: rimR)
                            var t = ctx.resolve(Text(hhmm(item.startMinute))
                                .font(.system(size: max(7, r * 0.07), weight: .semibold)))
                            t.shading = .color(.secondary)
                            var c = ctx
                            c.translateBy(x: p.x, y: p.y)
                            c.rotate(by: .radians(angle + .pi / 2 + (layout.textNeedsFlip(at: angle) ? .pi : 0)))
                            c.draw(t, at: .zero, anchor: .center)
                        }
                        drawClockHub(ctx, center: layout.center, radius: hubR, date: tick.date)
                    }
                    // White glyphs centered in each wedge (SF Symbols render cleanest as views).
                    ForEach(items) { item in
                        if let icon = item.symbolName, item.durationMinutes >= 35 {
                            let mid = (item.startMinute + item.durationMinutes / 2) % layout.minutesPerDay
                            let p = layout.point(forMinute: mid, radius: (inner + outer) / 2)
                            Image(systemName: icon)
                                .font(.system(size: max(11, r * 0.15), weight: .semibold))
                                .foregroundStyle(.white)
                                .opacity(item.isDone ? 0.7 : 1)
                                .position(p)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Day dial, \(items.count) blocks")
    }

    /// A small raised analog clock in the hub: white disc + 12 ticks + live hour/minute hands.
    private func drawClockHub(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, date: Date) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2))
            layer.fill(Path(ellipseIn: rect), with: .color(.white))
        }
        for hour in 0..<12 {
            let angle = -Double.pi / 2 + Double(hour) / 12 * 2 * .pi
            let p = pointAt(center, angle, radius * 0.78)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4)),
                     with: .color(.gray.opacity(0.5)))
        }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(comps.hour ?? 0), minute = Double(comps.minute ?? 0)
        let hourAngle = -Double.pi / 2 + ((hour.truncatingRemainder(dividingBy: 12) + minute / 60) / 12) * 2 * .pi
        let minuteAngle = -Double.pi / 2 + (minute / 60) * 2 * .pi
        ctx.stroke(Path { $0.move(to: center); $0.addLine(to: pointAt(center, hourAngle, radius * 0.5)) },
                   with: .color(Color(hex: "#0FB5C9") ?? .teal), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        ctx.stroke(Path { $0.move(to: center); $0.addLine(to: pointAt(center, minuteAngle, radius * 0.74)) },
                   with: .color(.red), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                 with: .color(Color(hex: "#0A6CC4") ?? .blue))
    }
}

// MARK: - Shared center time (donut hub)

@ViewBuilder
private func centerClockText(_ date: Date, holeRadius: CGFloat) -> some View {
    Text(date.formatted(date: .omitted, time: .shortened))
        .font(.system(size: max(13, holeRadius * 0.40), weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundStyle(.primary)
        .frame(width: holeRadius * 1.7)
}

// MARK: - Halo (the reimagined, information-first dial)

private func haloArc(_ layout: SectographLayout, _ item: SectographItem, radius: CGFloat) -> Path {
    let start = layout.angle(forMinute: item.startMinute)
    var end = layout.angle(forMinute: item.endMinute)
    if item.endMinute <= item.startMinute { end += 2 * .pi }
    if end - start < 0.01 { end = start + 0.01 }
    return Path { $0.addArc(center: layout.center, radius: radius, startAngle: .radians(start), endAngle: .radians(end), clockwise: false) }
}

private func haloDot(_ p: CGPoint, _ radius: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
}

private func haloContains(_ minute: Int, _ item: SectographItem) -> Bool {
    if item.endMinute >= item.startMinute { return minute >= item.startMinute && minute < item.endMinute }
    return minute >= item.startMinute || minute < item.endMinute
}

private func haloHHMM(_ minute: Int) -> String {
    let m = ((minute % 1440) + 1440) % 1440
    let h24 = m / 60, mm = m % 60
    let h12 = h24 % 12 == 0 ? 12 : h24 % 12
    return String(format: "%d:%02d %@", h12, mm, h24 < 12 ? "AM" : "PM")
}

/// "Halo" — the day as a soft ring, the present as a glowing bead, and the center answering
/// "what now / what next?". Past blocks recede; the current block brightens and glows. Designed to read
/// at a glance and feel native (SF Pro Rounded, system materials, Apple-Watch-ring bead language).
struct HaloDial: View {
    let items: [SectographItem]
    let titles: [String: String]

    private let nowTint = Color(hex: "#FF453A") ?? .red

    var body: some View {
        GeometryReader { geo in
            let layout = SectographLayout(size: geo.size, ringWidth: 1)
            let r = layout.outerRadius
            let trackR = r * 0.84
            let band = max(8.0, r * 0.11)
            let blocks = items.filter { !$0.isInstant }
            TimelineView(.periodic(from: .now, by: 60)) { tick in
                let now = dialMinuteOfDay(tick.date)
                ZStack {
                    Canvas { ctx, _ in
                        // Faint full-day track.
                        ctx.stroke(haloArc(layout, SectographItem(id: "_t", startMinute: 0, endMinute: 1439), radius: trackR),
                                   with: .color(.gray.opacity(0.13)), style: StrokeStyle(lineWidth: band, lineCap: .round))
                        // Cardinal anchors (12a top · 6a · 12p · 6p) as faint dots inside the ring.
                        for minute in stride(from: 0, to: 1440, by: 360) {
                            let p = layout.point(forMinute: minute, radius: trackR - band / 2 - 6)
                            ctx.fill(haloDot(p, 1.5), with: .color(.gray.opacity(0.35)))
                        }
                        // Blocks: past recedes, current brightens + glows, future stays vivid.
                        for item in blocks {
                            let base = Color(hex: item.colorHex) ?? .accentColor
                            let current = haloContains(now, item)
                            let past = !current && item.endMinute <= now && item.endMinute >= item.startMinute
                            let opacity = item.isDone ? 0.26 : (past ? 0.4 : (current ? 1.0 : 0.92))
                            let width = current ? band + 3 : band - 2
                            let path = haloArc(layout, item, radius: trackR)
                            if current && !item.isDone {
                                ctx.drawLayer { layer in
                                    layer.addFilter(.blur(radius: 7))
                                    layer.stroke(path, with: .color(base.opacity(0.55)),
                                                 style: StrokeStyle(lineWidth: width, lineCap: .round))
                                }
                            }
                            let p0 = layout.point(forMinute: item.startMinute, radius: trackR)
                            let p1 = layout.point(forMinute: item.endMinute, radius: trackR)
                            ctx.stroke(path, with: .linearGradient(
                                Gradient(colors: [base.opacity(opacity), base.opacity(opacity * 0.6)]),
                                startPoint: p0, endPoint: p1), style: StrokeStyle(lineWidth: width, lineCap: .round))
                        }
                        // Instant markers: a small tick on the ring.
                        for item in items where item.isInstant {
                            let p = layout.point(forMinute: item.startMinute, radius: trackR)
                            ctx.fill(haloDot(p, 3), with: .color(Color(hex: item.colorHex) ?? nowTint))
                        }
                        // The "now" bead — a glowing, white-ringed dot riding the track.
                        let bead = layout.point(forMinute: now, radius: trackR)
                        ctx.drawLayer { layer in
                            layer.addFilter(.blur(radius: 5))
                            layer.fill(haloDot(bead, 7), with: .color(nowTint.opacity(0.8)))
                        }
                        ctx.fill(haloDot(bead, 5.5), with: .color(.white))
                        ctx.fill(haloDot(bead, 3.5), with: .color(nowTint))
                    }
                    centerReadout(now: now, date: tick.date, innerRadius: trackR - band)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private func centerReadout(now: Int, date: Date, innerRadius: CGFloat) -> some View {
        let info = readout(now: now, date: date)
        VStack(spacing: 3) {
            Text(info.label)
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(info.isNow ? nowTint : .secondary)
            Text(info.title)
                .font(.system(size: max(15, innerRadius * 0.26), weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
            Text(info.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: innerRadius * 1.7)
    }

    private func readout(now: Int, date: Date) -> (label: String, title: String, detail: String, isNow: Bool) {
        let blocks = items.filter { !$0.isInstant }
        if let current = blocks.first(where: { haloContains(now, $0) }) {
            return ("NOW", titles[current.id] ?? "Busy",
                    "\(haloHHMM(current.startMinute)) – \(haloHHMM(current.endMinute))", true)
        }
        if let next = blocks.filter({ $0.startMinute > now }).min(by: { $0.startMinute < $1.startMinute }) {
            return ("NEXT", titles[next.id] ?? "Scheduled", "at \(haloHHMM(next.startMinute))", false)
        }
        return ("FREE", date.formatted(date: .omitted, time: .shortened), "nothing scheduled", false)
    }

    private var accessibilitySummary: String {
        let info = readout(now: dialMinuteOfDay(Date()), date: Date())
        return "Day dial. \(info.label): \(info.title), \(info.detail)"
    }
}

// MARK: - Sectograph Classic (faithful 12-hour clock reproduction)

/// A faithful reproduction of the classic "Sectograph" look: a 12-hour analog clock face (numerals +
/// minute ticks) with bold filled wedges sized by duration, titles written *radially* along each wedge,
/// 24-hour times on the rim, dashed outlines for upcoming events, a blue center hub, and a red now-hand
/// with a dashed tail. Built on a 12-hour ``SectographLayout`` (720-minute period) so angles match a
/// real clock; event minutes are placed by angle (which is periodic, so PM folds onto the 12h face).
struct ClassicDial: View {
    let items: [SectographItem]
    let titles: [String: String]

    var body: some View {
        GeometryReader { geo in
            let layout = SectographLayout(size: geo.size, ringWidth: 1, minutesPerDay: 720)
            let r = layout.outerRadius
            let faceR = r * 0.98
            let inner = r * 0.34, outer = r * 0.84
            let hubR = r * 0.26
            TimelineView(.periodic(from: .now, by: 60)) { tick in
                let nowAbs = dialMinuteOfDay(tick.date)
                ZStack {
                    Canvas { ctx, _ in
                        drawClockFace(ctx, layout, faceR: faceR, r: r)
                        for item in items where !item.isInstant {
                            drawWedge(ctx, layout, item, inner: inner, outer: outer, nowAbs: nowAbs, r: r)
                        }
                        for item in items where item.isInstant {
                            // Instant events: a short dashed spoke in the band.
                            let from = layout.point(forMinute: item.startMinute, radius: inner)
                            let to = layout.point(forMinute: item.startMinute, radius: outer)
                            ctx.stroke(Path { $0.move(to: from); $0.addLine(to: to) },
                                       with: .color(Color(hex: item.colorHex) ?? .red),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 3]))
                        }
                        drawNowHand(ctx, layout, nowAbs: nowAbs, faceR: faceR)
                    }
                    iconOverlays(layout, inner: inner, outer: outer, r: r)
                    centerHub(layout, date: tick.date, hubR: hubR)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Day dial, 12-hour clock, \(items.count) blocks")
    }

    // 60 minute ticks (major every 5) + hour numerals 1…12.
    private func drawClockFace(_ ctx: GraphicsContext, _ layout: SectographLayout, faceR: CGFloat, r: CGFloat) {
        for i in 0..<60 {
            let major = i % 5 == 0
            let angle = -Double.pi / 2 + Double(i) / 60 * 2 * .pi
            let o = pointAt(layout.center, angle, faceR)
            let inn = pointAt(layout.center, angle, faceR - (major ? 8 : 4))
            ctx.stroke(Path { $0.move(to: inn); $0.addLine(to: o) },
                       with: .color(.gray.opacity(major ? 0.55 : 0.25)), lineWidth: major ? 1 : 0.5)
        }
        for n in 1...12 {
            let angle = -Double.pi / 2 + Double(n) / 12 * 2 * .pi
            let p = pointAt(layout.center, angle, faceR * 0.91)
            var t = ctx.resolve(Text("\(n)").font(.system(size: max(9, r * 0.08))))
            t.shading = .color(.gray.opacity(0.85))
            ctx.draw(t, at: p, anchor: .center)
        }
    }

    private func drawWedge(_ ctx: GraphicsContext, _ layout: SectographLayout, _ item: SectographItem,
                           inner: CGFloat, outer: CGFloat, nowAbs: Int, r: CGFloat) {
        let base = Color(hex: item.colorHex) ?? .blue
        let future = item.startMinute > nowAbs && !item.isDone
        let wedge = annularWedge(layout, item.startMinute, item.endMinute, inner: inner, outer: outer, padDeg: 1)
        if future {
            ctx.stroke(wedge, with: .color(base), style: StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
        } else {
            ctx.fill(wedge, with: .color(base.opacity(item.isDone ? 0.85 : 1)))
        }
        guard item.durationMinutes >= 35 else { return }
        let mid = item.startMinute + item.durationMinutes / 2
        let midAngle = layout.angle(forMinute: mid)
        let flip = cos(midAngle) < 0

        // Radial title (reads along the spoke).
        if let title = titles[item.id], !title.isEmpty {
            let p = layout.point(forMinute: mid, radius: (inner + outer) / 2 + 3)
            var t = ctx.resolve(Text(title).font(.system(size: max(8, r * 0.072), weight: .semibold)))
            t.shading = .color(future ? base : .white)
            var c = ctx
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(midAngle + (flip ? .pi : 0)))
            c.draw(t, at: .zero, anchor: .center)
        }
        // Start time on the rim (tangent), white on the wedge's outer edge.
        let sa = layout.angle(forMinute: item.startMinute)
        let tp = layout.point(forMinute: item.startMinute, radius: outer - 9)
        var tt = ctx.resolve(Text(classicHM(item.startMinute)).font(.system(size: max(7, r * 0.058), weight: .medium)))
        tt.shading = .color(future ? base : .white.opacity(0.95))
        var tc = ctx
        tc.translateBy(x: tp.x, y: tp.y)
        tc.rotate(by: .radians(sa + .pi / 2 + (cos(sa) < 0 ? .pi : 0)))
        tc.draw(tt, at: .zero, anchor: .center)
    }

    private func drawNowHand(_ ctx: GraphicsContext, _ layout: SectographLayout, nowAbs: Int, faceR: CGFloat) {
        let angle = layout.angle(forMinute: nowAbs) // periodic → 12h position
        let tip = pointAt(layout.center, angle, faceR * 0.9)
        let dot = pointAt(layout.center, angle, faceR)
        ctx.stroke(Path { $0.move(to: layout.center); $0.addLine(to: tip) },
                   with: .color(.red), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        ctx.stroke(Path { $0.move(to: tip); $0.addLine(to: dot) },
                   with: .color(.red), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
        ctx.fill(haloDot(dot, 3.5), with: .color(.red))
    }

    @ViewBuilder
    private func iconOverlays(_ layout: SectographLayout, inner: CGFloat, outer: CGFloat, r: CGFloat) -> some View {
        ForEach(items) { item in
            if let icon = item.symbolName, !item.isInstant, item.durationMinutes >= 45 {
                let mid = item.startMinute + item.durationMinutes / 2
                let p = layout.point(forMinute: mid, radius: inner + (outer - inner) * 0.28)
                Image(systemName: icon)
                    .font(.system(size: max(9, r * 0.085), weight: .semibold))
                    .foregroundStyle(.white)
                    .position(p)
                    .accessibilityHidden(true)
            }
        }
    }

    private func centerHub(_ layout: SectographLayout, date: Date, hubR: CGFloat) -> some View {
        let c = Calendar.current.dateComponents([.hour, .minute, .day], from: date)
        let time = String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
        let weekday = date.formatted(.dateTime.weekday(.abbreviated)).lowercased()
        return Circle()
            .fill(Color(hex: "#1FA2E0") ?? .blue)
            .frame(width: hubR * 2, height: hubR * 2)
            .overlay(
                VStack(spacing: -1) {
                    Text(time).font(.system(size: max(13, hubR * 0.45), weight: .bold, design: .rounded))
                    Text("\(weekday) \(c.day ?? 0)").font(.system(size: max(8, hubR * 0.26), weight: .medium))
                }
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
            )
            .position(layout.center)
            .accessibilityHidden(true)
    }
}

private func classicHM(_ minute: Int) -> String { String(format: "%d:%02d", (minute / 60) % 24, minute % 60) }
