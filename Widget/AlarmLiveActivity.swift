// Alarm Live Activity (AppSpec §5.6, DevelopmentPlan P3-6).
//
// REFERENCE CODE — not yet compiled. Like FocusLiveActivity, this needs ActivityKit + a widget
// extension target + `NSSupportsLiveActivities` in Info.plist + signing + a device.
//
// iOS reality: a third-party app can't ring a true system alarm over silent/Focus the way Clock does.
// DoIT delivers alarms as Time-Sensitive notifications (see App/Features/Alarms/AlarmScheduler.swift)
// and, when `usesLiveActivity` is set, shows this lock-screen countdown so the next alarm stays glance-
// able. To wire it: move `AlarmActivityAttributes` into a shared framework and have `AlarmScheduler`
// `Activity.request(...)` it for the soonest alarm; `.end(...)` it when the alarm fires or is canceled.

import ActivityKit
import WidgetKit
import SwiftUI

/// The pending-alarm Live Activity payload. `fireAtEpoch` drives the system `.timer` countdown without
/// per-second app updates; mirrors `AlarmModel.fireAt`.
public struct AlarmActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var fireAtEpoch: Double

        public init(fireAtEpoch: Double) {
            self.fireAtEpoch = fireAtEpoch
        }
    }

    public var alarmTitle: String
    public var alarmId: String

    public init(alarmTitle: String, alarmId: String) {
        self.alarmTitle = alarmTitle
        self.alarmId = alarmId
    }
}

struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmActivityAttributes.self) { context in
            HStack(spacing: 10) {
                Image(systemName: "alarm.fill").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.alarmTitle).font(.headline).lineLimit(1)
                    countdown(context.state).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "alarm.fill") }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.alarmTitle).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) { countdown(context.state).font(.title2.monospacedDigit()) }
            } compactLeading: {
                Image(systemName: "alarm.fill")
            } compactTrailing: {
                countdown(context.state).monospacedDigit()
            } minimal: {
                Image(systemName: "alarm.fill")
            }
        }
    }

    /// Live-updating countdown to the alarm. `.timer` with a future date counts *down* automatically.
    @ViewBuilder
    private func countdown(_ state: AlarmActivityAttributes.ContentState) -> some View {
        Text(Date(timeIntervalSince1970: state.fireAtEpoch), style: .timer)
    }
}
