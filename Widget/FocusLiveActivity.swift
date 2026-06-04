// Focus-timer Live Activity (AppSpec §5.3, DevelopmentPlan P2-4).
//
// REFERENCE CODE — not yet compiled. Live Activities need ActivityKit + a widget extension target +
// `NSSupportsLiveActivities` in Info.plist + signing + a device. The elapsed math mirrors
// `SyncCore.FocusSession`. To wire it: move `FocusActivityAttributes` into a shared framework so the
// app's `FocusController` can `Activity.request(...)` / `.update(...)` it; see Widget/README.md.

import ActivityKit
import WidgetKit
import SwiftUI

/// The running-focus-block Live Activity payload. `ContentState` mirrors `FocusSession`'s fields so a
/// single elapsed model drives the in-app timer, the lock screen, and the Dynamic Island.
public struct FocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startedAtEpoch: Double?
        public var accumulatedSeconds: Double
        public var isRunning: Bool

        public init(startedAtEpoch: Double?, accumulatedSeconds: Double, isRunning: Bool) {
            self.startedAtEpoch = startedAtEpoch
            self.accumulatedSeconds = accumulatedSeconds
            self.isRunning = isRunning
        }
    }

    public var taskTitle: String
    public var taskId: String

    public init(taskTitle: String, taskId: String) {
        self.taskTitle = taskTitle
        self.taskId = taskId
    }
}

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            HStack(spacing: 10) {
                Image(systemName: "timer").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.taskTitle).font(.headline).lineLimit(1)
                    elapsed(context.state).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "timer") }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.taskTitle).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) { elapsed(context.state).font(.title2.monospacedDigit()) }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                elapsed(context.state).monospacedDigit()
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }

    /// Live-updating elapsed time. Counting from `started - accumulated` makes the system's `.timer`
    /// style show *total* elapsed (current run + prior runs) without per-second app updates.
    @ViewBuilder
    private func elapsed(_ state: FocusActivityAttributes.ContentState) -> some View {
        if let started = state.startedAtEpoch, state.isRunning {
            Text(Date(timeIntervalSince1970: started - state.accumulatedSeconds), style: .timer)
        } else {
            Text("Paused")
        }
    }
}
