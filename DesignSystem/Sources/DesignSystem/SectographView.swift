import SwiftUI

/// Light/dark styling for the dial. `.auto` follows the environment color scheme; `.dark` forces the
/// night palette (e.g. for a future dark widget).
public enum SectographStyle: Sendable { case auto, light, dark }

/// The sectograph — DoIT's 24-hour radial day-dial (AppSpec §5.3), "Premium Aurora" treatment. Renders
/// today's blocks as gradient arcs on a day→night twilight backdrop, with on-arc titles, a live frosted
/// center hub, dashed markers for due-only items, and a glowing now-hand. All geometry comes from the
/// pure ``SectographLayout`` (unit-tested); this view is just the `Canvas` + overlays, so the same core
/// also drives the widgets and Live Activity. Effects are tasteful and Reduce-Motion-gated.
public struct SectographView: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let items: [SectographItem]
    private let busy: [SectographItem]
    /// Accessible description per item id (e.g. "Deep work, 9:00 to 11:00 AM") for VoiceOver.
    private let labels: [String: String]
    /// On-arc display titles, keyed by item id (out-of-band, like `labels`). Empty → no titles drawn.
    private let titles: [String: String]
    private let ringWidth: CGFloat
    private let showNowHand: Bool
    private let showCenterHub: Bool
    private let showDayNightBackdrop: Bool
    private let style: SectographStyle

    /// Entrance reveal (0→1): the dial fades + scales in on appear. Collapsed to 1 under Reduce Motion.
    @State private var appear: CGFloat = 0

    public init(items: [SectographItem], busy: [SectographItem] = [], labels: [String: String] = [:],
                titles: [String: String] = [:], ringWidth: CGFloat = 24, showNowHand: Bool = true,
                showCenterHub: Bool = true, showDayNightBackdrop: Bool = true,
                style: SectographStyle = .auto) {
        self.items = items
        self.busy = busy
        self.labels = labels
        self.titles = titles
        self.ringWidth = ringWidth
        self.showNowHand = showNowHand
        self.showCenterHub = showCenterHub
        self.showDayNightBackdrop = showDayNightBackdrop
        self.style = style
    }

    private var isDark: Bool {
        switch style {
        case .light: return false
        case .dark: return true
        case .auto: return colorScheme == .dark
        }
    }

    public var body: some View {
        GeometryReader { geo in
            let layout = SectographLayout(size: geo.size, ringWidth: ringWidth)
            ZStack {
                if showDayNightBackdrop { dayNightBackdrop(layout) }

                // The clock-driven layers (arc emphasis, hub time, now-hand) share one TimelineView so
                // they advance together once a minute — a discrete jump, inherently Reduce-Motion-safe.
                TimelineView(.periodic(from: .now, by: 60)) { tick in
                    let nowMinute = minuteOfDay(tick.date)
                    ZStack {
                        Canvas { context, _ in
                            drawTrack(context, layout)
                            drawBusy(context, layout)
                            drawHourTicks(context, layout)
                            drawArcs(context, layout, nowMinute: nowMinute)
                            drawArcLabels(context, layout)
                            drawInstantSpokes(context, layout)
                        }
                        if showCenterHub { centerHub(layout, date: tick.date) }
                        if showNowHand && !reduceMotion { nowHand(layout, minute: nowMinute) }
                    }
                }

                instantMarkerChips(layout) // static SF-Symbol chips just outside the rim
            }
            .opacity(reduceMotion ? 1 : Double(appear))
            .scaleEffect(reduceMotion ? 1 : 0.94 + 0.06 * appear)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            if reduceMotion { appear = 1 }
            else { withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { appear = 1 } }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: items)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Day dial — \(items.count) scheduled blocks")
        .accessibilityChildren {
            VStack(spacing: 1) {
                ForEach(items) { item in
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(labels[item.id] ?? "Scheduled block")
                }
            }
        }
        .accessibilityRotor("Scheduled blocks") {
            ForEach(items) { item in
                AccessibilityRotorEntry(labels[item.id] ?? "Scheduled block", id: item.id)
            }
        }
    }

    // MARK: - Backdrop

    /// A dawn→day→dusk→night twilight wash behind the ring. `AngularGradient` starts at 3 o'clock and
    /// sweeps clockwise; the dial is midnight-at-top/clockwise, so `angle: -90°` aligns minute 0 to the
    /// top and noon (fraction 0.5) to the bottom. Kept low-opacity + blurred so it reads as a glow.
    private func dayNightBackdrop(_ layout: SectographLayout) -> some View {
        let diameter = layout.outerRadius * 2
        return AngularGradient(gradient: Gradient(stops: isDark ? Self.nightStops : Self.dayStops),
                               center: .center, angle: .degrees(-90))
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .opacity(isDark ? 0.55 : 0.32)
            .blur(radius: 10)
            .position(layout.center)
    }

    /// Twilight stops in fraction-of-day order (first == last so the midnight seam is invisible).
    private static let dayStops: [Gradient.Stop] = [
        .init(color: Color(red: 0.10, green: 0.12, blue: 0.28), location: 0.00), // midnight
        .init(color: Color(red: 0.42, green: 0.36, blue: 0.56), location: 0.18), // pre-dawn
        .init(color: Color(red: 0.99, green: 0.71, blue: 0.55), location: 0.26), // dawn
        .init(color: Color(red: 0.70, green: 0.86, blue: 1.00), location: 0.36), // morning
        .init(color: Color(red: 0.99, green: 0.98, blue: 0.92), location: 0.50), // noon
        .init(color: Color(red: 0.80, green: 0.89, blue: 1.00), location: 0.66), // afternoon
        .init(color: Color(red: 0.99, green: 0.64, blue: 0.44), location: 0.79), // dusk
        .init(color: Color(red: 0.52, green: 0.31, blue: 0.50), location: 0.88), // twilight
        .init(color: Color(red: 0.10, green: 0.12, blue: 0.28), location: 1.00), // midnight
    ]

    private static let nightStops: [Gradient.Stop] = [
        .init(color: Color(red: 0.04, green: 0.05, blue: 0.14), location: 0.00),
        .init(color: Color(red: 0.16, green: 0.15, blue: 0.30), location: 0.18),
        .init(color: Color(red: 0.55, green: 0.34, blue: 0.34), location: 0.26),
        .init(color: Color(red: 0.20, green: 0.34, blue: 0.55), location: 0.36),
        .init(color: Color(red: 0.36, green: 0.46, blue: 0.64), location: 0.50),
        .init(color: Color(red: 0.22, green: 0.33, blue: 0.53), location: 0.66),
        .init(color: Color(red: 0.50, green: 0.27, blue: 0.30), location: 0.79),
        .init(color: Color(red: 0.20, green: 0.14, blue: 0.30), location: 0.88),
        .init(color: Color(red: 0.04, green: 0.05, blue: 0.14), location: 1.00),
    ]

    // MARK: - Canvas layers

    private func drawTrack(_ context: GraphicsContext, _ layout: SectographLayout) {
        let path = Path { p in
            p.addArc(center: layout.center, radius: layout.midRadius,
                     startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        }
        context.stroke(path, with: .color(theme.colors.separator.opacity(0.35)), lineWidth: ringWidth)
    }

    private func drawHourTicks(_ context: GraphicsContext, _ layout: SectographLayout) {
        for hour in 0..<24 {
            let minute = hour * 60
            let isMajor = hour % 6 == 0
            let outer = layout.point(forMinute: minute, radius: layout.outerRadius)
            let inner = layout.point(forMinute: minute,
                                     radius: layout.outerRadius - (isMajor ? ringWidth : ringWidth / 2))
            let path = Path { p in p.move(to: inner); p.addLine(to: outer) }
            context.stroke(path, with: .color(theme.colors.separator.opacity(isMajor ? 0.8 : 0.4)),
                           lineWidth: isMajor ? 1.5 : 0.75)
        }
    }

    /// Free/busy events from the calendar (P2-5) — a muted band behind the task arcs.
    private func drawBusy(_ context: GraphicsContext, _ layout: SectographLayout) {
        for arc in layout.arcs(for: busy) {
            let path = Path { p in
                p.addArc(center: layout.center, radius: layout.midRadius,
                         startAngle: .radians(arc.startAngle),
                         endAngle: .radians(max(arc.endAngle, arc.startAngle + 0.01)), clockwise: false)
            }
            context.stroke(path, with: .color(theme.colors.separator.opacity(0.85)),
                           style: StrokeStyle(lineWidth: ringWidth - 2, lineCap: .butt))
        }
    }

    /// Gradient-filled task arcs. The block holding "now" (or a caller-emphasized one) is thicker,
    /// brighter, and gets a soft glow; completed blocks recede. Instant items are drawn as spokes.
    private func drawArcs(_ context: GraphicsContext, _ layout: SectographLayout, nowMinute: Int) {
        for item in items where !item.isInstant {
            let path = arcPath(for: item, layout: layout)
            let base = Color(hex: item.colorHex) ?? theme.colors.accent
            let emphasized = item.isEmphasized || layout.contains(minute: nowMinute, item)
            let lineW = ringWidth - (emphasized ? 1 : 4)
            let hi = item.isDone ? 0.30 : (emphasized ? 1.00 : 0.92)
            let lo = item.isDone ? 0.16 : (emphasized ? 0.70 : 0.55)

            let start = layout.point(forMinute: item.startMinute, radius: layout.midRadius)
            let end = layout.point(forMinute: item.endMinute, radius: layout.midRadius)

            // Soft glow under the current/important block (static — safe regardless of Reduce Motion).
            if emphasized && !item.isDone {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 6))
                    layer.stroke(path, with: .color(base.opacity(0.5)),
                                 style: StrokeStyle(lineWidth: lineW, lineCap: .round))
                }
            }
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [base.opacity(hi), base.opacity(lo)]), startPoint: start, endPoint: end)
            context.stroke(path, with: shading, style: StrokeStyle(lineWidth: lineW, lineCap: .round))
        }
    }

    /// One arc stroke path along the centerline, sweeping forward (adds 2π on a midnight wrap so the
    /// block draws the long way around instead of collapsing to a sliver).
    private func arcPath(for item: SectographItem, layout: SectographLayout) -> Path {
        let startAngle = layout.angle(forMinute: item.startMinute)
        var endAngle = layout.angle(forMinute: item.endMinute)
        if item.endMinute <= item.startMinute { endAngle += 2 * .pi }
        if endAngle - startAngle < 0.01 { endAngle = startAngle + 0.01 } // guarantee a visible sliver
        return Path { p in
            p.addArc(center: layout.center, radius: layout.midRadius,
                     startAngle: .radians(startAngle), endAngle: .radians(endAngle), clockwise: false)
        }
    }

    /// Event titles drawn along each arc, tangent to the ring and kept upright on the left half.
    private func drawArcLabels(_ context: GraphicsContext, _ layout: SectographLayout) {
        for item in items where !item.isInstant {
            guard let title = titles[item.id], !title.isEmpty else { continue }
            let midMinute = (item.startMinute + item.durationMinutes / 2) % layout.minutesPerDay
            let point = layout.point(forMinute: midMinute, radius: layout.midRadius)

            guard layout.shouldLabel(item, charCount: title.count) else {
                // Too short for text: a faint leader dot if there's still a little room, else nothing.
                if layout.arcLength(for: item) >= 10 {
                    let dot = Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3))
                    context.fill(dot, with: .color(.white.opacity(item.isDone ? 0.4 : 0.85)))
                }
                continue
            }

            let angle = layout.midAngle(for: item)
            let available = max(12, layout.arcLength(for: item) - 8)
            // Truncate to what fits (~7pt/char) — Canvas draws at a point, so we size the string here
            // rather than relying on a line-limited layout (Text's lineLimit isn't a Text-returning op).
            let maxChars = max(1, Int(available / 7))
            let shown = title.count > maxChars ? String(title.prefix(max(1, maxChars - 1))) + "…" : title
            var text = context.resolve(Text(shown).font(.caption2.weight(.semibold)))
            text.shading = .color(.white)

            var ctx = context
            ctx.addFilter(.shadow(color: .black.opacity(0.5), radius: 1.5))
            ctx.translateBy(x: point.x, y: point.y)
            ctx.rotate(by: .radians(angle + .pi / 2 + (layout.textNeedsFlip(at: angle) ? .pi : 0)))
            ctx.draw(text, at: .zero, anchor: .center)
        }
    }

    /// Dashed radial spokes for due-only (instant) items.
    private func drawInstantSpokes(_ context: GraphicsContext, _ layout: SectographLayout) {
        for item in items where item.isInstant {
            let from = layout.point(forMinute: item.startMinute, radius: layout.innerRadius)
            let to = layout.point(forMinute: item.startMinute, radius: layout.outerRadius)
            let base = Color(hex: item.colorHex) ?? theme.colors.statusOverdue
            let path = Path { p in p.move(to: from); p.addLine(to: to) }
            context.stroke(path, with: .color(base.opacity(item.isDone ? 0.4 : 0.95)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3]))
        }
    }

    // MARK: - Overlays

    /// Small colored chips (list SF Symbol) pinned just outside the rim for each instant marker.
    @ViewBuilder
    private func instantMarkerChips(_ layout: SectographLayout) -> some View {
        ForEach(items.filter { $0.isInstant }) { item in
            let point = layout.point(forMinute: item.startMinute, radius: layout.outerRadius + 9)
            let base = Color(hex: item.colorHex) ?? theme.colors.statusOverdue
            Image(systemName: item.symbolName ?? "bell.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Circle().fill(base.opacity(item.isDone ? 0.5 : 1)))
                .position(point)
                .accessibilityHidden(true)
        }
    }

    /// Frosted center hub showing the live time + weekday. Font scales with the dial so it fits both the
    /// 240pt Today hero and a small widget. Decorative → hidden from VoiceOver (the rotor lists blocks).
    private func centerHub(_ layout: SectographLayout, date: Date) -> some View {
        let diameter = layout.innerRadius * 1.15
        let timeSize = min(32, max(15, layout.innerRadius * 0.32))
        return VStack(spacing: 1) {
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: timeSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: timeSize * 0.44, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .minimumScaleFactor(0.5)
        .frame(width: diameter, height: diameter)
        .background(Circle().fill(.ultraThinMaterial))
        .position(layout.center)
        .accessibilityHidden(true)
    }

    /// The now-hand: a glowing red hand from the hub to the rim, a tip dot, and a hub knob.
    private func nowHand(_ layout: SectographLayout, minute: Int) -> some View {
        let tip = layout.point(forMinute: minute, radius: layout.outerRadius)
        let color = theme.colors.statusOverdue
        return ZStack {
            Path { p in p.move(to: layout.center); p.addLine(to: tip) }
                .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .blur(radius: 4)
            Path { p in p.move(to: layout.center); p.addLine(to: tip) }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            Circle().fill(color).frame(width: 6, height: 6).position(tip)
            Circle().fill(color)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .frame(width: 10, height: 10)
                .position(layout.center)
        }
    }

    // MARK: - Helpers

    private func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
