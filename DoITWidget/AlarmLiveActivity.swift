// Routine / alarm-chain Live Activity (AppSpec §5.6, DevelopmentPlan P3-6).
//
// REFERENCE CODE — not yet compiled. Like FocusLiveActivity, this needs ActivityKit + a widget
// extension target + `NSSupportsLiveActivities` in Info.plist + signing + a device.
//
// iOS reality: a third-party app can't ring a true system alarm over silent/Focus the way Clock does.
// DoIT delivers a routine's per-step alarms as Time-Sensitive notifications (see
// App/Features/Alarms/AlarmScheduler.swift); when the routine is running this Live Activity tracks the
// chain — the current step, progress through the steps, and a live countdown to the next step — so the
// flow stays glanceable on the lock screen + Dynamic Island. To wire it: move `RoutineActivityAttributes`
// into a shared framework and have the materializer/`AlarmScheduler` `Activity.request/update/end` it as
// the chain advances.

import ActivityKit
import WidgetKit
import SwiftUI

/// The running-routine Live Activity payload. `nextStepAtEpoch` drives the system `.timer` countdown to
/// the next step without per-second app updates; `stepIndex`/`stepCount` drive the progress bar.
public struct RoutineActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var stepTitle: String
        public var stepIndex: Int       // 1-based
        public var stepCount: Int
        public var nextStepAtEpoch: Double?

        public init(stepTitle: String, stepIndex: Int, stepCount: Int, nextStepAtEpoch: Double?) {
            self.stepTitle = stepTitle
            self.stepIndex = stepIndex
            self.stepCount = stepCount
            self.nextStepAtEpoch = nextStepAtEpoch
        }
    }

    public var routineTitle: String
    public var routineId: String

    public init(routineTitle: String, routineId: String) {
        self.routineTitle = routineTitle
        self.routineId = routineId
    }
}

struct RoutineLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoutineActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "checklist").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(context.state.stepTitle).font(.headline).lineLimit(1)
                        Text("step \(context.state.stepIndex) of \(context.state.stepCount)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    progress(context.state)
                }
                Spacer()
                countdown(context.state).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "checklist").foregroundStyle(.tint) }
                DynamicIslandExpandedRegion(.trailing) { countdown(context.state).font(.title3.monospacedDigit()) }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.stepTitle).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) { progress(context.state) }
            } compactLeading: {
                Image(systemName: "checklist")
            } compactTrailing: {
                countdown(context.state).monospacedDigit().frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "checklist")
            }
            .keylineTint(.teal)
        }
    }

    @ViewBuilder
    private func progress(_ state: RoutineActivityAttributes.ContentState) -> some View {
        ProgressView(value: Double(state.stepIndex), total: Double(max(1, state.stepCount))).tint(.teal)
    }

    /// Live countdown to the next step (`.timer` with a future date counts down automatically).
    @ViewBuilder
    private func countdown(_ state: RoutineActivityAttributes.ContentState) -> some View {
        if let next = state.nextStepAtEpoch {
            Text(Date(timeIntervalSince1970: next), style: .timer)
        } else {
            Text("Last step")
        }
    }
}
