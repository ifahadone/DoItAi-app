import Foundation
import Observation
import SyncCore

/// Owns the single in-flight focus session (DevelopmentPlan P2-4). `@Observable` so the timer UI +
/// (future) Live Activity react to start/pause/resume. The elapsed math lives in the pure
/// ``SyncCore/FocusSession``; this just stamps it with the injected ``Clock`` and surfaces the logged
/// minutes on stop.
@Observable
@MainActor
final class FocusController {
    private(set) var session: FocusSession?
    private let clock: Clock

    init(clock: Clock) {
        self.clock = clock
    }

    var isActive: Bool { session != nil }

    private var now: Double { clock.now().timeIntervalSince1970 }

    func start(taskId: String, title: String) {
        session = FocusSession(taskId: taskId, taskTitle: title).started(at: now)
    }

    func pause() { session = session?.paused(at: now) }
    func resume() { session = session?.started(at: now) }

    /// Stop the session, returning `(taskId, loggedMinutes)` to persist, and clear it.
    func stop() -> (taskId: String, minutes: Int)? {
        guard let session else { return nil }
        let result = (session.taskId, session.loggedMinutes(at: now))
        self.session = nil
        return result
    }
}
