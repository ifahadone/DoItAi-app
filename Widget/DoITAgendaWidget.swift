// DoIT agenda widget (AppSpec §5.9, DevelopmentPlan P1-J).
//
// REFERENCE CODE — not yet compiled. A WidgetKit extension needs its own Xcode target, which the
// hand-authored DoIT.xcodeproj does not have. See Widget/README.md for the integration steps. This
// file is written against `SyncCore` (the agenda snapshot) + the app's `CompleteTaskIntent` so it
// drops in once the target + App Group + signing are configured.
//
// Data flow (decoupled — the widget never touches SwiftData): the app publishes an `AgendaSnapshot`
// to the shared App-Group `UserDefaults` on each sync (`AppServices.publishAgenda`); the widget reads
// it here. Interactive completion uses `CompleteTaskIntent` (must be shared with this target).

import WidgetKit
import SwiftUI
import AppIntents
import SyncCore

// MARK: - Timeline

struct AgendaEntry: TimelineEntry {
    let date: Date
    let snapshot: AgendaSnapshot
}

struct AgendaProvider: TimelineProvider {
    /// The App-Group suite the app writes the snapshot to. Must match `AppConfig.appGroupIdentifier`.
    private static let appGroup = "group.app.doit"

    private func currentSnapshot() -> AgendaSnapshot {
        let defaults = UserDefaults(suiteName: Self.appGroup) ?? .standard
        return AgendaSnapshotStore.load(from: defaults)
    }

    func placeholder(in context: Context) -> AgendaEntry {
        AgendaEntry(date: Date(), snapshot: AgendaSnapshot(items: [
            AgendaItem(taskId: "p", title: "Your next task", dueText: "9:00 AM", priorityLevel: 3),
        ], generatedAtEpoch: 0))
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        completion(AgendaEntry(date: Date(), snapshot: currentSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        // Refresh hourly; the app also nudges via WidgetCenter.reloadTimelines after edits.
        let entry = AgendaEntry(date: Date(), snapshot: currentSnapshot())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - View

struct AgendaWidgetView: View {
    var entry: AgendaEntry

    private var openItems: [AgendaItem] { entry.snapshot.items.filter { !$0.isDone } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today").font(.headline)
            if openItems.isEmpty {
                Text("All clear ✨").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(openItems.prefix(4)) { item in
                    HStack(spacing: 8) {
                        // Interactive completion (iOS 17 App Intents in widgets).
                        Button(intent: CompleteTaskIntent(taskId: item.taskId)) {
                            Image(systemName: "circle")
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.subheadline).lineLimit(1)
                            if let due = item.dueText {
                                Text(due).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if (1...4).contains(item.priorityLevel) {
                            Image(systemName: "flag.fill").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
                if openItems.count > 4 {
                    Text("+\(openItems.count - 4) more").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget + Bundle

struct AgendaWidget: Widget {
    let kind = "DoITAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgendaProvider()) { entry in
            AgendaWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Agenda")
        .description("Your due + overdue DoIT tasks. Tap a circle to complete one.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DoITWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgendaWidget()
    }
}
