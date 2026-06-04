import Foundation

/// A focus-timer session for a task (AppSpec §5.3 "focus timer", DevelopmentPlan P2-4). Pure value —
/// elapsed time is derived from `startedAtEpoch` (when the current run began, `nil` while paused) plus
/// `accumulatedSeconds` (completed runs), evaluated against an injected `now`. The same value drives
/// the in-app timer and the Live Activity, and on stop yields the `actualMinutes` to log on the task.
public struct FocusSession: Equatable, Sendable {
    public var taskId: String
    public var taskTitle: String
    /// Epoch seconds the current run started; `nil` while paused.
    public var startedAtEpoch: Double?
    /// Seconds from prior (paused) runs.
    public var accumulatedSeconds: Double

    public init(taskId: String, taskTitle: String, startedAtEpoch: Double? = nil, accumulatedSeconds: Double = 0) {
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.startedAtEpoch = startedAtEpoch
        self.accumulatedSeconds = accumulatedSeconds
    }

    public var isRunning: Bool { startedAtEpoch != nil }

    public func elapsedSeconds(at now: Double) -> Double {
        accumulatedSeconds + (startedAtEpoch.map { max(0, now - $0) } ?? 0)
    }

    /// Elapsed minutes (rounded) — what gets logged as the task's `actualMinutes`.
    public func loggedMinutes(at now: Double) -> Int {
        Int((elapsedSeconds(at: now) / 60).rounded())
    }

    /// Begin (or resume) running. No-op if already running.
    public func started(at now: Double) -> FocusSession {
        guard !isRunning else { return self }
        return FocusSession(taskId: taskId, taskTitle: taskTitle, startedAtEpoch: now, accumulatedSeconds: accumulatedSeconds)
    }

    /// Pause — fold the current run into `accumulatedSeconds`. No-op if already paused.
    public func paused(at now: Double) -> FocusSession {
        guard let startedAt = startedAtEpoch else { return self }
        return FocusSession(taskId: taskId, taskTitle: taskTitle, startedAtEpoch: nil,
                            accumulatedSeconds: accumulatedSeconds + max(0, now - startedAt))
    }
}
