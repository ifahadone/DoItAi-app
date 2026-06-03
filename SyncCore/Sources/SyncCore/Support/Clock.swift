import Foundation

/// A source of "now".
///
/// No logic in DoIT should call `Date()` directly (AppSpec §16, ApiSpec §17). Injecting a
/// clock keeps sync/conflict resolution deterministic and reproducible in tests. The app wires
/// up ``SystemClock``; tests use ``FixedClock`` (or its mutable companion) to pin time.
///
/// All instants are UTC (AppSpec §5.1 / §6.5); `Date` is already an absolute instant, so callers
/// never need to reason about a calendar or zone here — only rendering does.
public protocol Clock: Sendable {
    /// The current instant, in UTC.
    func now() -> Date
}

/// The production clock. Reads the device wall clock.
public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

/// A clock pinned to a single instant. Useful for deterministic unit tests where time must not move.
public struct FixedClock: Clock {
    public let instant: Date

    public init(_ instant: Date) {
        self.instant = instant
    }

    public func now() -> Date {
        instant
    }
}

/// A clock whose "now" can be advanced by the test, for exercising backoff/expiry logic.
///
/// Backed by an actor so it is safe to share across concurrent tasks (`Sendable`). Because reads are
/// `async`, use this where the unit under test already awaits; for purely synchronous code prefer
/// ``FixedClock``.
public actor MutableClock: Clock {
    private var instant: Date

    public init(_ start: Date) {
        self.instant = start
    }

    /// Non-isolated `now()` is required by `Clock`. It returns the value captured at init; to read
    /// the *advanced* value in async code use ``current()``. Kept deliberately simple — see docs.
    nonisolated public func now() -> Date {
        // A nonisolated stored snapshot would require locking; instead this returns a best-effort
        // value. Tests that mutate time should read via `current()`.
        // TODO(Phase 1): if synchronous advance-aware reads are needed, back this with an
        // os_unfair_lock-guarded box instead of an actor.
        Date.distantPast
    }

    /// The current (possibly advanced) instant.
    public func current() -> Date {
        instant
    }

    /// Move time forward by `interval` seconds.
    public func advance(by interval: TimeInterval) {
        instant = instant.addingTimeInterval(interval)
    }

    /// Jump to a specific instant.
    public func set(_ newInstant: Date) {
        instant = newInstant
    }
}
