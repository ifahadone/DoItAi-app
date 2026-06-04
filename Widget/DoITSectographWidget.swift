// DoIT sectograph (day-dial) widget (AppSpec §5.3, DevelopmentPlan P2-6).
//
// REFERENCE CODE — not yet compiled. Like the agenda widget it needs a widget extension target +
// App Group + signing (see Widget/README.md). It reuses `DesignSystem.SectographView` (the same dial
// the Today hero uses) over the blocks published in the App-Group `AgendaSnapshot` — so the home/lock
// screen and the app render from one layout core, satisfying the Phase-2 DoD.

import WidgetKit
import SwiftUI
import SyncCore
import DesignSystem

struct SectographEntry: TimelineEntry {
    let date: Date
    let snapshot: AgendaSnapshot
}

struct SectographProvider: TimelineProvider {
    private static let appGroup = "group.app.doit"

    private func currentSnapshot() -> AgendaSnapshot {
        AgendaSnapshotStore.load(from: UserDefaults(suiteName: Self.appGroup) ?? .standard)
    }

    func placeholder(in context: Context) -> SectographEntry {
        SectographEntry(date: Date(), snapshot: .empty)
    }
    func getSnapshot(in context: Context, completion: @escaping (SectographEntry) -> Void) {
        completion(SectographEntry(date: Date(), snapshot: currentSnapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SectographEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [SectographEntry(date: Date(), snapshot: currentSnapshot())], policy: .after(next)))
    }
}

struct SectographWidgetView: View {
    var entry: SectographEntry

    /// Snapshot blocks that carry a start minute become dial arcs (the same model the app uses).
    private var items: [SectographItem] {
        entry.snapshot.items.compactMap { item in
            guard let start = item.startMinute else { return nil }
            return SectographItem(id: item.taskId, startMinute: start,
                                  endMinute: item.endMinute ?? min(1440, start + 30))
        }
    }

    var body: some View {
        // The small widget is too dense for the center hub + twilight backdrop; degrade to the clean
        // ring + now-hand (titles also absent — the snapshot carries no colors/titles here).
        SectographView(items: items, ringWidth: 16, showNowHand: true,
                       showCenterHub: false, showDayNightBackdrop: false)
            .padding(6)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct SectographWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoITSectographWidget", provider: SectographProvider()) { entry in
            SectographWidgetView(entry: entry)
        }
        .configurationDisplayName("Day Dial")
        .description("Your day at a glance on the sectograph.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}
