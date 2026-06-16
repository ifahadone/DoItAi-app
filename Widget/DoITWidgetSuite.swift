// DoIT widget suite — Home Screen + Lock Screen widgets + the widget bundle (AppSpec §5.9, P1-J / P2-6).
//
// REFERENCE CODE — not yet compiled. WidgetKit needs its own Xcode extension target (the hand-authored
// DoIT.xcodeproj doesn't have one). See Widget/README.md for the integration steps. Everything here is
// written against `SyncCore` (the enriched `AgendaSnapshot`) + the app's `CompleteTaskIntent` so it
// drops straight in once the target + App Group + signing exist.
//
// Data flow (decoupled — widgets never touch SwiftData): the app writes an enriched `AgendaSnapshot`
// to the shared App-Group `UserDefaults` on each sync (`AppServices.publishAgenda`, which also calls
// `WidgetCenter.reloadAllTimelines()`); the widgets read it here.

import WidgetKit
import SwiftUI
import AppIntents
import SyncCore
import DesignSystem

// MARK: - Shared snapshot loading

enum WidgetData {
    /// Must match `AppConfig.appGroupIdentifier`.
    static let appGroup = "group.app.doit"

    static func snapshot() -> AgendaSnapshot {
        let defaults = UserDefaults(suiteName: appGroup) ?? .standard
        return AgendaSnapshotStore.load(from: defaults)
    }

    /// The block happening now (scheduled interval contains the current minute), else nil.
    static func current(_ snapshot: AgendaSnapshot, nowMinute: Int) -> AgendaItem? {
        snapshot.items.first { item in
            guard let s = item.startMinute, let e = item.endMinute, !item.isDone else { return false }
            return s <= nowMinute && nowMinute < e
        }
    }

    /// The soonest upcoming item (by start, else by any scheduled start) after `nowMinute`.
    static func next(_ snapshot: AgendaSnapshot, nowMinute: Int, excluding currentId: String?) -> AgendaItem? {
        snapshot.items
            .filter { !$0.isDone && $0.taskId != currentId && ($0.startMinute ?? -1) > nowMinute }
            .min { ($0.startMinute ?? 0) < ($1.startMinute ?? 0) }
    }

    static func nowMinute(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func color(_ hex: String?) -> Color { Color(hex: hex) ?? .accentColor }
}

// MARK: - Timeline (shared)

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: AgendaSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: AgendaSnapshot(items: [
            AgendaItem(taskId: "p1", title: "Morning run", dueText: "7:00 AM", startMinute: 420, endMinute: 465, colorHex: "#34C759"),
            AgendaItem(taskId: "p2", title: "Deep work", dueText: "9:00 AM", startMinute: 540, endMinute: 660, colorHex: "#0A84FF"),
        ], generatedAtEpoch: 0, completedToday: 4, totalToday: 9, focusMinutesToday: 95,
           topHabit: HabitSummary(name: "Workout", streakCurrent: 7, recent: [true, true, false, true, true, true, true])))
    }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetData.snapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // Refresh on the next 15-minute boundary so the now/next + now-line stay fresh; the app also
        // nudges via WidgetCenter after edits/sync.
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetData.snapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Up Next (small · lock rectangular · lock inline)

struct UpNextWidget: Widget {
    let kind = "DoITUpNext"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            UpNextView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Up Next")
        .description("What's happening now and what's next.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct UpNextView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    private var nowMin: Int { WidgetData.nowMinute(entry.date) }
    private var current: AgendaItem? { WidgetData.current(entry.snapshot, nowMinute: nowMin) }
    private var next: AgendaItem? { WidgetData.next(entry.snapshot, nowMinute: nowMin, excluding: current?.taskId) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label((next ?? current)?.shortLine ?? "All clear", systemImage: "circle.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                if let cur = current {
                    Text("NOW \(cur.title)").font(.headline).lineLimit(1)
                } else if let nxt = next {
                    Text(nxt.title).font(.headline).lineLimit(1)
                } else { Text("All clear").font(.headline) }
                if let nxt = next { Text("Next · \(nxt.dueText ?? nxt.title)").font(.caption).lineLimit(1) }
            }
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cur = current {
                HStack(spacing: 5) {
                    Circle().fill(WidgetData.color(cur.colorHex)).frame(width: 7, height: 7)
                    Text("NOW").font(.caption2.weight(.bold)).foregroundStyle(WidgetData.color(cur.colorHex))
                }
                Spacer(minLength: 4)
                Text(cur.title).font(.headline).lineLimit(2)
                if let due = cur.dueText { Text(due).font(.caption2).foregroundStyle(.secondary) }
            } else if let nxt = next {
                Text("UP NEXT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(nxt.title).font(.headline).lineLimit(2)
            } else {
                Text("All clear").font(.headline)
                Text("Nothing scheduled").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if let nxt = next, current != nil {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.secondary)
                    Text(nxt.title).font(.caption2).lineLimit(1)
                    if let d = nxt.dueText { Text("· \(d)").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Today (medium · large) — interactive completion

struct TodayWidget: Widget {
    let kind = "DoITToday"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            TodayView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your day's progress + agenda. Tap a circle to complete.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    private var open: [AgendaItem] { entry.snapshot.items.filter { !$0.isDone } }
    private var rowLimit: Int { family == .systemLarge ? 7 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                let done = entry.snapshot.completedToday, total = entry.snapshot.totalToday
                if total > 0 {
                    Text("\(done) of \(total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    ProgressView(value: Double(done), total: Double(max(1, total)))
                        .frame(width: 44).tint(.accentColor)
                }
            }
            if open.isEmpty {
                Spacer(); Text("All clear ✨").font(.subheadline).foregroundStyle(.secondary); Spacer()
            } else {
                ForEach(open.prefix(rowLimit)) { item in
                    HStack(spacing: 8) {
                        Button(intent: CompleteTaskIntent(taskId: item.taskId)) { Image(systemName: "circle") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 2).fill(WidgetData.color(item.colorHex)).frame(width: 3, height: 16)
                        Text(item.title).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 0)
                        if let due = item.dueText { Text(due).font(.caption2).foregroundStyle(.secondary).monospacedDigit() }
                    }
                }
                if open.count > rowLimit {
                    Text("+\(open.count - rowLimit) more").font(.caption2).foregroundStyle(.secondary)
                }
                if family == .systemLarge { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Streak (small · lock circular)

struct StreakWidget: Widget {
    let kind = "DoITStreak"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            StreakView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Your top habit's streak + the last week.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct StreakView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry
    private var habit: HabitSummary? { entry.snapshot.topHabit }

    var body: some View {
        if family == .accessoryCircular {
            Gauge(value: Double(min(habit?.streakCurrent ?? 0, 30)), in: 0...30) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(habit?.streakCurrent ?? 0)")
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                    Text("\(habit?.streakCurrent ?? 0)").font(.title.weight(.semibold)).monospacedDigit()
                    Text("days").font(.caption).foregroundStyle(.secondary).padding(.bottom, 3).alignmentGuide(.bottom) { $0[.bottom] }
                }
                Spacer(minLength: 4)
                Text(habit?.name ?? "No habit yet").font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    ForEach(Array((habit?.recent ?? []).enumerated()), id: \.offset) { _, done in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(done ? Color.green : Color.secondary.opacity(0.2))
                            .frame(height: 20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Bundle

@main
struct DoITWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
        TodayWidget()
        StreakWidget()
        SectographWidget()   // DoITSectographWidget.swift (small/medium dial + lock circular)
        DayPlanWidget()      // DoITSectographWidget.swift (large: dial + agenda)
        if #available(iOS 18.0, *) { QuickAddControl() } // DoITControl.swift (Control Center)
        // Live Activities (FocusLiveActivity / RoutineLiveActivity) register automatically via ActivityKit.
    }
}

// MARK: - Small helpers

private extension AgendaItem {
    var shortLine: String { dueText.map { "\(title) · \($0)" } ?? title }
}
