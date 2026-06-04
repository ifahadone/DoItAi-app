import XCTest
@testable import SyncCore

final class FocusSessionTests: XCTestCase {
    func testElapsedWhileRunning() {
        let s = FocusSession(taskId: "t", taskTitle: "Write", startedAtEpoch: 1000, accumulatedSeconds: 0)
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.elapsedSeconds(at: 1060), 60, accuracy: 1e-9)
        XCTAssertEqual(s.loggedMinutes(at: 1090), 2) // 90s → rounds to 2 min
    }

    func testPauseFoldsIntoAccumulated() {
        let running = FocusSession(taskId: "t", taskTitle: "Write", startedAtEpoch: 1000)
        let paused = running.paused(at: 1060)
        XCTAssertFalse(paused.isRunning)
        XCTAssertEqual(paused.accumulatedSeconds, 60, accuracy: 1e-9)
        XCTAssertEqual(paused.elapsedSeconds(at: 9999), 60, accuracy: 1e-9) // frozen while paused
    }

    func testResumeAddsToAccumulated() {
        let s = FocusSession(taskId: "t", taskTitle: "Write")
            .started(at: 0)
            .paused(at: 60)        // 60s
            .started(at: 100)      // resume
        XCTAssertEqual(s.elapsedSeconds(at: 130), 90, accuracy: 1e-9) // 60 + 30
    }

    func testStartIsIdempotentAndPauseNoOpWhenPaused() {
        let running = FocusSession(taskId: "t", taskTitle: "x").started(at: 0)
        XCTAssertEqual(running.started(at: 50), running) // already running → unchanged
        let paused = running.paused(at: 60)
        XCTAssertEqual(paused.paused(at: 90), paused)    // already paused → unchanged
    }
}
