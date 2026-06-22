// Focus-timer Live Activity (AppSpec §5.3, DevelopmentPlan P2-4).
//
// REFERENCE CODE — not yet compiled. Live Activities need ActivityKit + a widget extension target +
// `NSSupportsLiveActivities` in Info.plist + signing + a device. The elapsed model mirrors
// `SyncCore.FocusSession`. To wire it: move `FocusActivityAttributes` into a shared framework so the
// app's `FocusController` can `Activity.request/update/end` it; the pause/stop buttons are
// `LiveActivityIntent`s the app's `FocusController` handles (see Widget/README.md).

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// The running-focus-block Live Activity payload. `ContentState` mirrors `FocusSession`'s fields (plus
/// a `targetSeconds` for the ring) so one elapsed model drives the in-app timer, the lock screen, and
/// the Dynamic Island.
public struct FocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startedAtEpoch: Double?
        public var accumulatedSeconds: Double
        public var isRunning: Bool
        /// Target length of the focus block (for the ring); defaults to a 25-minute pomodoro.
        public var targetSeconds: Double

        public init(startedAtEpoch: Double?, accumulatedSeconds: Double, isRunning: Bool, targetSeconds: Double = 1500) {
            self.startedAtEpoch = startedAtEpoch
            self.accumulatedSeconds = accumulatedSeconds
            self.isRunning = isRunning
            self.targetSeconds = targetSeconds
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
            // Lock-screen / banner presentation.
            HStack(spacing: 14) {
                ring(context.state).frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.taskTitle).font(.headline).lineLimit(1)
                    elapsed(context.state).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                controls(context.state, taskId: context.attributes.taskId)
            }
            .padding()
            .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { ring(context.state).frame(width: 40, height: 40) }
                DynamicIslandExpandedRegion(.trailing) { controls(context.state, taskId: context.attributes.taskId) }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.taskTitle).font(.headline).lineLimit(1)
                        elapsed(context.state).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.tint)
            } compactTrailing: {
                elapsed(context.state).monospacedDigit().frame(maxWidth: 56)
            } minimal: {
                ring(context.state)
            }
            .keylineTint(.indigo)
        }
    }

    /// Auto-advancing focus ring (no per-second app updates): `ProgressView(timerInterval:)` fills over
    /// the block from its start; paused shows the static fraction.
    @ViewBuilder
    private func ring(_ state: FocusActivityAttributes.ContentState) -> some View {
        if let started = state.startedAtEpoch, state.isRunning {
            let start = Date(timeIntervalSince1970: started - state.accumulatedSeconds)
            ProgressView(timerInterval: start...start.addingTimeInterval(state.targetSeconds), countsDown: false) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
            .progressViewStyle(.circular)
            .tint(.indigo)
        } else {
            ProgressView(value: min(1, state.accumulatedSeconds / max(1, state.targetSeconds)))
                .progressViewStyle(.circular).tint(.gray)
        }
    }

    /// Total elapsed (current run + prior runs) via the system timer style — no per-second updates.
    @ViewBuilder
    private func elapsed(_ state: FocusActivityAttributes.ContentState) -> some View {
        if let started = state.startedAtEpoch, state.isRunning {
            Text(Date(timeIntervalSince1970: started - state.accumulatedSeconds), style: .timer)
        } else {
            Text("Paused")
        }
    }

    /// Interactive pause/resume + stop (LiveActivityIntents handled by the app's FocusController).
    @ViewBuilder
    private func controls(_ state: FocusActivityAttributes.ContentState, taskId: String) -> some View {
        HStack(spacing: 10) {
            if #available(iOS 17.0, *) {
                Button(intent: ToggleFocusIntent(taskId: taskId)) {
                    Image(systemName: state.isRunning ? "pause.fill" : "play.fill")
                }.buttonStyle(.plain)
                Button(intent: StopFocusIntent(taskId: taskId)) {
                    Image(systemName: "stop.fill")
                }.buttonStyle(.plain).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Live Activity intents (handled in-app by FocusController via a shared App-Group flag)

@available(iOS 17.0, *)
struct ToggleFocusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume focus"
    @Parameter(title: "Task ID") var taskId: String
    init() {}
    init(taskId: String) { self.taskId = taskId }
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.app.doit")?.set("toggle:\(taskId)", forKey: "doit.focusControl")
        return .result()
    }
}

@available(iOS 17.0, *)
struct StopFocusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop focus"
    @Parameter(title: "Task ID") var taskId: String
    init() {}
    init(taskId: String) { self.taskId = taskId }
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.app.doit")?.set("stop:\(taskId)", forKey: "doit.focusControl")
        return .result()
    }
}
