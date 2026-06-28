import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// Apple-Calendar-style planner (AppSpec §5.3): Day / Week / Month views over the user's scheduled
/// tasks, with a navigation header (prev/next + Today) and a scale switcher. The Day view reuses the
/// interactive ``DayGridView`` (tap-to-create, long-press drag-move/resize, drag-to-schedule tray,
/// free/busy backdrop, now-line); Week + Month are overview/navigation surfaces. Tapping a day in
/// Week/Month drills into the Day view for that date.
struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services

    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil && !$0.archived && $0.statusRaw != 4 })
    private var tasks: [TaskModel]
    @Query(filter: #Predicate<TaskListModel> { $0.deletedAt == nil })
    private var lists: [TaskListModel]

    enum Scale: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month"
        var id: String { rawValue }
    }

    @State private var scale: Scale = .day
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var selectedTask: TaskModel?
    /// Finger-tracking pager (month + week): live drag offset + measured page width, plus guards so a
    /// commit-in-flight isn't re-entered and only horizontal-dominant drags page.
    @State private var dragOffset: CGFloat = 0
    @State private var pageWidth: CGFloat = 0
    @State private var isPaging = false
    @State private var isHorizontalDrag = false
    /// EventKit free/busy authorization, refreshed on appear; drives the "Connect your calendar" card.
    @State private var calendarAuthorized = false
    @State private var showCalendarSelection = false
    @State private var daySlotMinutes = 60

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: services.clock.now()) }
    private var dayHourHeight: CGFloat { 56 * 60 / CGFloat(daySlotMinutes) }
    private let daySlotOptions = [10, 20, 30, 60, 90, 120]
    private func addMonths(_ n: Int) -> Date { cal.startOfDay(for: cal.date(byAdding: .month, value: n, to: selectedDate) ?? selectedDate) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch scale {
            case .day: dayView
            case .week: weekView
            case .month: monthView
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task).environment(auth).environment(services)
        }
        .sheet(isPresented: $showCalendarSelection) {
            CalendarSelectionView().environment(services)
        }
        .task { calendarAuthorized = services.calendar.isAuthorized }
        .onAppear {
            #if DEBUG
            if let s = AppConfig.calendarScale, let v = Scale(rawValue: s.capitalized) { scale = v }
            #endif
        }
    }

    // MARK: - Header (title · prev/next · Today · scale switcher)

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                Button("Today") { if !isPaging { withAnimation { selectedDate = today } } }
                    .font(.subheadline)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
            }
            Picker("View", selection: $scale.animation()) {
                ForEach(Scale.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal).padding(.top, 6).padding(.bottom, 8)
    }

    private var title: String {
        switch scale {
        case .day:
            return selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .week:
            let days = weekDays(of: selectedDate)
            let start = days.first ?? selectedDate, end = days.last ?? selectedDate
            let s = start.formatted(.dateTime.month(.abbreviated).day())
            let e = end.formatted(cal.isDate(start, equalTo: end, toGranularity: .month)
                                  ? .dateTime.day() : .dateTime.month(.abbreviated).day())
            return "\(s) – \(e)"
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private func step(_ direction: Int) {
        if scale == .day {
            if let next = cal.date(byAdding: .day, value: direction, to: selectedDate) {
                withAnimation(.easeInOut(duration: 0.28)) { selectedDate = cal.startOfDay(for: next) }
            }
            return
        }
        guard !isPaging else { return } // ignore chevron taps while a page commit is in flight
        if pageWidth > 0 { slideAndCommit(dir: direction, to: direction > 0 ? -pageWidth : pageWidth) }
        else { withAnimation(.easeInOut(duration: 0.25)) { advance(dir: direction) } }
    }

    /// Advance the paging anchor by one page of the current scale. Month normalizes to the 1st so
    /// forward/back paging round-trips exactly (Calendar's month-add otherwise clamps Jan 31 → Feb 28,
    /// drifting the selected day).
    private func advance(dir: Int) {
        switch scale {
        case .month:
            selectedDate = firstOfMonth(addMonths(dir))
        case .week:
            if let next = cal.date(byAdding: .weekOfYear, value: dir, to: selectedDate) {
                selectedDate = cal.startOfDay(for: next)
            }
        case .day:
            break
        }
    }

    private func firstOfMonth(_ date: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? cal.startOfDay(for: date)
    }

    /// End-of-drag decision for the carousel: only page on a horizontal-dominant drag past a
    /// quarter-width; otherwise snap back. Clears the horizontal-drag flag.
    private func endPageDrag(_ dx: CGFloat, width w: CGFloat) {
        let horizontal = isHorizontalDrag
        isHorizontalDrag = false
        guard horizontal else { withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }; return }
        let threshold = w / 4
        if dx < -threshold { slideAndCommit(dir: 1, to: -w) }
        else if dx > threshold { slideAndCommit(dir: -1, to: w) }
        else { withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 } }
    }

    /// Animate the strip to the adjacent page, then recentre on the new page with animations disabled —
    /// driven by the animation's own completion (no timer/clock race) and guarded against re-entry and
    /// a mid-flight scale switch.
    private func slideAndCommit(dir: Int, to offset: CGFloat) {
        guard !isPaging else { return }
        isPaging = true
        let startScale = scale
        withAnimation(.easeOut(duration: 0.22)) {
            dragOffset = offset
        } completion: {
            var txn = Transaction(); txn.disablesAnimations = true
            withTransaction(txn) {
                if scale == startScale { advance(dir: dir) }
                dragOffset = 0
            }
            isPaging = false
        }
    }

    /// Generic finger-tracking 3-page carousel (prev | current | next) shared by month + week. The drag
    /// is `.simultaneousGesture` + horizontal-dominance-gated so each page's inner vertical scroll still
    /// works; pages commit through ``slideAndCommit``.
    private func pagingStrip<Page: View>(@ViewBuilder page: @escaping (Int) -> Page) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                page(-1).frame(width: w)
                page(0).frame(width: w)
                page(1).frame(width: w)
            }
            .offset(x: -w + dragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard !isPaging else { return }
                        if abs(value.translation.width) > abs(value.translation.height) {
                            isHorizontalDrag = true
                            dragOffset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        guard !isPaging else { return }
                        endPageDrag(value.translation.width, width: w)
                    }
            )
            .onAppear { pageWidth = w }
        }
    }

    // MARK: - Day view

    private var dayView: some View {
        VStack(spacing: 0) {
            calendarPermissionCard
            // TimelineView ticks each minute so the red now-line advances live (Apple-Calendar style).
            TimelineView(.periodic(from: Date(), by: 60)) { _ in
                DayGridView(
                    items: dayItems(selectedDate),
                    titles: titles(for: selectedDate),
                    busy: busyItems(for: selectedDate),
                    hourHeight: dayHourHeight,
                    markerStepMinutes: daySlotMinutes,
                    splitDayAtNoon: true,
                    onCreate: { minute in Task { await createBlock(at: minute, on: selectedDate) } },
                    onMove: { id, start in Task { await move(id, toStart: start, on: selectedDate) } },
                    onResize: { id, end in Task { await resize(id, toEnd: end, on: selectedDate) } },
                    onTap: { id in selectedTask = tasks.first { $0.id == id } },
                    onDropSchedule: { id, minute in Task { await schedule(id, at: minute, on: selectedDate) } },
                    nowMinute: cal.isDate(selectedDate, inSameDayAs: today) ? currentMinute() : nil
                )
            }
            if !unscheduled.isEmpty { tray }
        }
    }

    private var dayScaleControl: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Timeline scale")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(daySlotLabel)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(daySlotOptions.enumerated()), id: \.element) { index, minutes in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { daySlotMinutes = minutes }
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Rectangle()
                                        .fill(index == 0 ? Color.clear : theme.colors.separator.opacity(0.45))
                                        .frame(height: 1)
                                        .offset(x: -28)
                                    Capsule()
                                        .fill(minutes == daySlotMinutes ? theme.colors.accent : theme.colors.separator)
                                        .frame(width: 2, height: minutes == daySlotMinutes ? 18 : 10)
                                }
                                Text(daySlotTickLabel(minutes))
                                    .font(.system(size: 10, weight: minutes == daySlotMinutes ? .semibold : .medium))
                                    .foregroundStyle(minutes == daySlotMinutes ? theme.colors.accent : .secondary)
                                    .monospacedDigit()
                            }
                            .frame(width: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(daySlotAccessibilityLabel(minutes)) timeline scale")
                        .accessibilityValue(minutes == daySlotMinutes ? "Selected" : "")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private var daySlotAccessibilityLabel: String {
        daySlotAccessibilityLabel(daySlotMinutes)
    }

    private func daySlotAccessibilityLabel(_ minutesValue: Int) -> String {
        let hours = minutesValue / 60
        let minutes = minutesValue % 60
        if hours == 0 { return "\(minutes) minute slot" }
        if minutes == 0 { return "\(hours) hour slot" }
        return "\(hours) hour \(minutes) minute slot"
    }

    private func daySlotTickLabel(_ minutes: Int) -> String {
        return "\(minutes)m"
    }

    private var daySlotLabel: String {
        "\(daySlotMinutes)m"
    }

    /// S07: ask for Apple Calendar access at the Plan moment (not up front), so the day grid can show
    /// busy times. Device-bound — on the simulator the prompt no-ops, but the flow is wired here.
    @ViewBuilder private var calendarPermissionCard: some View {
        if !calendarAuthorized {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(theme.colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your calendar").font(.subheadline.weight(.medium))
                    Text("See busy times from Apple Calendar here. Read on this device only.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Connect") {
                    Task { calendarAuthorized = await services.calendar.requestAccess() }
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(theme.spacing.md)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.medium))
            .padding(.horizontal)
            .padding(.top, theme.spacing.sm)
        } else {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: "calendar").foregroundStyle(theme.colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calendars in free/busy").font(.subheadline.weight(.medium))
                    Text("Choose which calendars show as busy. Read on this device only.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose") { showCalendarSelection = true }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(theme.spacing.md)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.medium))
            .padding(.horizontal)
            .padding(.top, theme.spacing.sm)
        }
    }

    // MARK: - Week view

    /// Week view as the shared finger-tracking 3-page carousel (prev | current | next). The horizontal
    /// pager drag is dominance-gated + `.simultaneousGesture`, so each page's vertical timeline still
    /// scrolls; paging shifts `selectedDate` by a week and recentres seamlessly (no TabView snap-flash).
    private var weekView: some View {
        pagingStrip { offset in weekPageView(forOffset: offset) }
    }

    private func weekPageView(forOffset n: Int) -> some View {
        let base = cal.date(byAdding: .weekOfYear, value: n, to: selectedDate) ?? selectedDate
        let days = weekDays(of: base)
        let grid = DayGridLayout(hourHeight: 44)
        return VStack(spacing: 0) {
            weekHeader(days)
            Divider()
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    hourAxis(grid)
                    ForEach(days, id: \.self) { day in
                        weekColumn(day, grid: grid)
                            .overlay(Rectangle().frame(width: 0.5).frame(maxHeight: .infinity)
                                .foregroundStyle(theme.colors.separator.opacity(0.4)), alignment: .leading)
                    }
                }
            }
        }
    }

    private func weekHeader(_ days: [Date]) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 38)
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDate(day, inSameDayAs: today)
                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .background(isToday ? Color.red : .clear, in: Circle())
                        .foregroundStyle(isToday ? .white : .primary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { selectedDate = day; scale = .day } }
            }
        }
        .padding(.vertical, 6)
    }

    private func hourAxis(_ grid: DayGridLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1..<24, id: \.self) { hour in
                Text(hourLabel(hour)).font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
                    .position(x: 19, y: grid.y(forMinute: hour * 60))
            }
        }
        .frame(width: 38, height: grid.totalHeight, alignment: .topLeading)
    }

    private func weekColumn(_ day: Date, grid: DayGridLayout) -> some View {
        let items = dayItems(day)
        let lanes = Dictionary(uniqueKeysWithValues: DayGridPacker.assign(items).map { ($0.id, $0) })
        let isToday = cal.isDate(day, inSameDayAs: today)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(0..<24, id: \.self) { hour in
                    Path { p in
                        let y = grid.y(forMinute: hour * 60)
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }.stroke(theme.colors.separator.opacity(0.25), lineWidth: 0.5)
                }
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in
                        Task { await createBlock(at: grid.snap(grid.minute(forY: v.location.y)), on: day) }
                    })
                ForEach(items) { item in
                    let lane = lanes[item.id] ?? LaneAssignment(id: item.id, lane: 0, laneCount: 1)
                    let w = geo.size.width / CGFloat(max(1, lane.laneCount))
                    let color = Color(hex: item.colorHex) ?? theme.colors.accent
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.85))
                        .overlay(alignment: .topLeading) {
                            Text(titles(for: day)[item.id] ?? "")
                                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
                                .lineLimit(2).padding(.horizontal, 2).padding(.top, 1)
                        }
                        .frame(width: max(0, w - 1), height: max(12, grid.height(forDuration: item.durationMinutes)), alignment: .topLeading)
                        .offset(x: w * CGFloat(lane.lane), y: grid.y(forMinute: item.startMinute))
                        .onTapGesture { selectedTask = tasks.first { $0.id == item.id } }
                }
                if isToday {
                    TimelineView(.periodic(from: Date(), by: 60)) { _ in
                        let ny = grid.y(forMinute: currentMinute())
                        Path { p in p.move(to: CGPoint(x: 0, y: ny)); p.addLine(to: CGPoint(x: geo.size.width, y: ny)) }
                            .stroke(Color.red, lineWidth: 1)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: grid.totalHeight)
        }
        .frame(height: grid.totalHeight)
    }

    // MARK: - Month view

    private var monthView: some View {
        let symbols = MonthGridBuilder.make(for: selectedDate, calendar: cal).weekdaySymbols
        let gridHeight: CGFloat = 48 * 6
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, sym in
                    Text(sym).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            Divider()
            // Interactive 3-page month pager (prev | current | next) that follows the finger.
            pagingStrip { offset in monthGrid(for: addMonths(offset)) }
                .frame(height: gridHeight)
                .clipped()
            Divider()
            // …with the selected day's agenda listed below (Apple-Calendar month layout).
            agendaList
        }
    }

    /// The 6×7 month grid for `date` (one pager page).
    private func monthGrid(for date: Date) -> some View {
        let g = MonthGridBuilder.make(for: date, calendar: cal)
        return VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(g.weeks[row]) { day in monthCell(day, height: 48) }
                }
            }
        }
    }

    /// Agenda for the selected day, beneath the month grid: time-sorted rows of that day's events/due
    /// tasks. Tapping a day in the grid updates this list; tapping a row opens the task.
    private var agendaList: some View {
        let entries = agenda(for: selectedDate)
        return List {
            Section {
                if entries.isEmpty {
                    Text("Nothing scheduled").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(entries, id: \.task.id) { entry in
                        HStack(spacing: 10) {
                            Text(entry.timeLabel)
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                .frame(width: 92, alignment: .leading)
                            RoundedRectangle(cornerRadius: 2).fill(color(for: entry.task)).frame(width: 3, height: 22)
                            Text(entry.task.title).font(.subheadline).lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTask = entry.task }
                    }
                }
            } header: {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            }
        }
        .listStyle(.plain)
    }

    private func color(for task: TaskModel) -> Color {
        task.listId.flatMap { id in lists.first { $0.id == id }?.colorHex }.flatMap { Color(hex: $0) } ?? theme.colors.accent
    }

    private struct AgendaEntry { let task: TaskModel; let timeLabel: String; let sort: Int }
    private func agenda(for date: Date) -> [AgendaEntry] {
        func minute(_ d: Date) -> Int { let c = cal.dateComponents([.hour, .minute], from: d); return (c.hour ?? 0) * 60 + (c.minute ?? 0) }
        func timeStr(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
        var entries: [AgendaEntry] = []
        for task in tasksOn(date) {
            if let s = task.scheduledStart, cal.isDate(s, inSameDayAs: date) {
                let label = task.scheduledEnd.map { "\(timeStr(s)) – \(timeStr($0))" } ?? timeStr(s)
                entries.append(AgendaEntry(task: task, timeLabel: label, sort: minute(s)))
            } else if let d = task.dueAt, cal.isDate(d, inSameDayAs: date) {
                entries.append(AgendaEntry(task: task, timeLabel: "Due \(timeStr(d))", sort: minute(d)))
            }
        }
        return entries.sorted { $0.sort < $1.sort }
    }

    private func monthCell(_ day: MonthGrid.Day, height: CGFloat) -> some View {
        let isToday = cal.isDate(day.date, inSameDayAs: today)
        let isSelected = cal.isDate(day.date, inSameDayAs: selectedDate)
        let dayTasks = tasksOn(day.date)
        return VStack(spacing: 3) {
            Text(day.date.formatted(.dateTime.day()))
                .font(.callout)
                .frame(width: 26, height: 26)
                .background(isToday ? Color.red : (isSelected ? theme.colors.accent.opacity(0.18) : .clear), in: Circle())
                .foregroundStyle(isToday ? .white : (day.inMonth ? .primary : .secondary.opacity(0.5)))
            HStack(spacing: 2) {
                ForEach(dayTasks.prefix(3), id: \.id) { task in
                    Circle()
                        .fill(task.listId.flatMap { id in lists.first { $0.id == id }?.colorHex }
                            .flatMap { Color(hex: $0) } ?? theme.colors.accent)
                        .frame(width: 5, height: 5)
                }
                if dayTasks.count > 3 { Text("+\(dayTasks.count - 3)").font(.system(size: 8)).foregroundStyle(.secondary) }
            }
            .frame(height: 6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .padding(.top, 4)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(theme.colors.separator.opacity(0.4)), alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { selectedDate = day.date } } // select → updates the agenda below
    }

    // MARK: - Unscheduled tray (day view)

    private var unscheduled: [TaskModel] {
        // Truly unscheduled (no time block), so the tray is stable regardless of which day is selected.
        tasks
            .filter { $0.status != .done && $0.scheduledStart == nil }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: 6) {
            dayScaleControl
            Divider().padding(.horizontal, 12)
            Text("Drag to schedule").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(unscheduled) { task in
                        trayChip(task).draggable(task.id) { trayChip(task).opacity(0.9) }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func trayChip(_ task: TaskModel) -> some View {
        let color = task.listId.flatMap { id in lists.first { $0.id == id }?.colorHex }
            .flatMap { Color(hex: $0) } ?? .accentColor
        return Text(task.title)
            .font(.caption).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(color)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Data

    private func weekDays(of date: Date) -> [Date] {
        guard let start = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return [date] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func currentMinute() -> Int {
        let c = cal.dateComponents([.hour, .minute], from: services.clock.now())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour { case 0: return "12a"; case 12: return "12p"; case let h where h < 12: return "\(h)a"; default: return "\(hour - 12)p" }
    }

    /// Tasks rendered as blocks on `date`: scheduled ranges; due-only tasks as 30-min markers.
    private func dayItems(_ date: Date) -> [SectographItem] {
        func minute(_ d: Date) -> Int? {
            guard cal.isDate(d, inSameDayAs: date) else { return nil }
            let c = cal.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        return tasks.compactMap { task in
            let color = task.listId.flatMap { id in lists.first { $0.id == id }?.colorHex }
            if let start = task.scheduledStart, let sm = minute(start) {
                let em = task.scheduledEnd.flatMap(minute) ?? min(1440, sm + 60)
                return SectographItem(id: task.id, startMinute: sm, endMinute: em, colorHex: color)
            } else if let due = task.dueAt, let dm = minute(due) {
                return SectographItem(id: task.id, startMinute: dm, endMinute: min(1440, dm + 30), colorHex: color)
            }
            return nil
        }
    }

    private func titles(for date: Date) -> [String: String] {
        Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    }

    /// Tasks scheduled or due on `date` (for month dots).
    private func tasksOn(_ date: Date) -> [TaskModel] {
        tasks.filter { task in
            if let s = task.scheduledStart, cal.isDate(s, inSameDayAs: date) { return true }
            if let d = task.dueAt, cal.isDate(d, inSameDayAs: date) { return true }
            return false
        }
    }

    private func busyItems(for date: Date) -> [SectographItem] {
        #if DEBUG
        if AppConfig.isCalendarDemo && cal.isDate(date, inSameDayAs: today) {
            return [
                SectographItem(id: "busy:standup", startMinute: 11 * 60, endMinute: 12 * 60),
                SectographItem(id: "busy:review", startMinute: 14 * 60, endMinute: 15 * 60 + 30),
            ]
        }
        #endif
        // EventKit free/busy is queried for "now"; only meaningful for today's grid.
        return cal.isDate(date, inSameDayAs: today) ? services.calendar.busyItems(now: services.clock.now()) : []
    }

    // MARK: - Mutations

    private var mutation: TaskMutation {
        TaskMutation(context: modelContext, engine: services.syncEngine, clock: services.clock, idGenerator: services.idGenerator)
    }
    private var ownerId: String {
        if case let .signedIn(userId) = auth.state, let userId { return userId }
        return "local-user"
    }
    private func syncIfLive() async { if AppConfig.isLiveSync { await services.syncOnce() } }

    private func date(atMinute minute: Int, on day: Date) -> Date {
        // Resolve the wall-clock time via components (DST-correct) rather than adding minutes to midnight.
        let m = max(0, min(1439, minute))
        return cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day) ?? cal.startOfDay(for: day)
    }
    private func minuteOfDay(_ d: Date) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: d); return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    private func durationMinutes(_ task: TaskModel) -> Int {
        if let s = task.scheduledStart, let e = task.scheduledEnd { return max(15, Int(e.timeIntervalSince(s) / 60)) }
        return 60
    }
    private func fetch(_ id: String) -> TaskModel? {
        var d = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? modelContext.fetch(d).first
    }

    private func createBlock(at minute: Int, on day: Date) async {
        let creator = TaskCreation(context: modelContext, engine: services.syncEngine, ownerId: ownerId,
                                   clock: services.clock, idGenerator: services.idGenerator)
        let id = await creator.createTask(title: "New block")
        if let task = tasks.first(where: { $0.id == id }) ?? fetch(id) {
            await mutation.setSchedule(task, start: date(atMinute: minute, on: day),
                                       end: date(atMinute: min(1440, minute + 60), on: day))
        }
        await syncIfLive()
    }
    private func move(_ id: String, toStart startMinute: Int, on day: Date) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let dur = durationMinutes(task)
        await mutation.setSchedule(task, start: date(atMinute: startMinute, on: day),
                                   end: date(atMinute: min(1440, startMinute + dur), on: day))
        await syncIfLive()
    }
    private func resize(_ id: String, toEnd endMinute: Int, on day: Date) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let startMinute = task.scheduledStart.map(minuteOfDay) ?? max(0, endMinute - 60)
        await mutation.setSchedule(task, start: date(atMinute: startMinute, on: day),
                                   end: date(atMinute: max(startMinute + 15, endMinute), on: day))
        await syncIfLive()
    }
    private func schedule(_ id: String, at minute: Int, on day: Date) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        await mutation.setSchedule(task, start: date(atMinute: minute, on: day),
                                   end: date(atMinute: min(1440, minute + 60), on: day))
        await syncIfLive()
    }
}
