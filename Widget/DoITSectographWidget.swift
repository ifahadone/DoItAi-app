// DoIT sectograph (day-dial) widgets (AppSpec §5.3, DevelopmentPlan P2-6).
//
// REFERENCE CODE — not yet compiled (needs a widget extension target + App Group + signing; see
// Widget/README.md). Reuses `DesignSystem.SectographView` — the SAME dial the Today hero uses — over
// the blocks published in the App-Group `AgendaSnapshot`, now with the list colors the snapshot
// carries. So the home/lock screen and the app render from one layout core (the Phase-2 DoD).
//
// Providers/entry come from DoITWidgetSuite.swift (`SnapshotProvider` / `SnapshotEntry`).

import WidgetKit
import SwiftUI
import SyncCore
import DesignSystem

private func dialItems(_ snapshot: AgendaSnapshot) -> [SectographItem] {
    snapshot.items.compactMap { item in
        guard let start = item.startMinute else { return nil }
        return SectographItem(id: item.taskId, startMinute: start,
                              endMinute: item.endMinute ?? min(1440, start + 30),
                              colorHex: item.colorHex, isDone: item.isDone)
    }
}

// MARK: - Day Dial (small · lock circular)

struct SectographWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoITSectograph", provider: SnapshotProvider()) { entry in
            SectographWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Day Dial")
        .description("Your day at a glance on the sectograph.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct SectographWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        // Lock-screen circular: a dense monochrome dial (the system tints accessory widgets); home
        // small: the clean colored ring + now-hand (no hub/backdrop — too dense at that size).
        SectographView(items: dialItems(entry.snapshot), ringWidth: family == .accessoryCircular ? 10 : 16,
                       showNowHand: true, showCenterHub: false, showDayNightBackdrop: false)
            .padding(family == .accessoryCircular ? 0 : 6)
            .widgetAccentable(family == .accessoryCircular)
    }
}

// MARK: - Day Plan (large) — dial + agenda

struct DayPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoITDayPlan", provider: SnapshotProvider()) { entry in
            DayPlanWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Day Plan")
        .description("The dial plus the rest of your day.")
        .supportedFamilies([.systemLarge])
    }
}

struct DayPlanWidgetView: View {
    var entry: SnapshotEntry

    private var agenda: [AgendaItem] {
        entry.snapshot.items
            .filter { $0.startMinute != nil && !$0.isDone }
            .sorted { ($0.startMinute ?? 0) < ($1.startMinute ?? 0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SectographView(items: dialItems(entry.snapshot), ringWidth: 14,
                           showNowHand: true, showCenterHub: true, showDayNightBackdrop: true)
                .frame(width: 132, height: 132)
            VStack(alignment: .leading, spacing: 7) {
                Text("Today").font(.headline)
                if agenda.isEmpty {
                    Text("Nothing scheduled").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(agenda.prefix(6)) { item in
                        HStack(spacing: 7) {
                            Text(item.dueText ?? "").font(.caption2).foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .leading).monospacedDigit()
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: item.colorHex) ?? .accentColor)
                                .frame(width: 3, height: 14)
                            Text(item.title).font(.caption).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
