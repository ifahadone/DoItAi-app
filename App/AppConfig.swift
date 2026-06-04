import Foundation

/// Static app configuration resolved at launch (AppSpec §7, ApiSpec §3).
///
/// Values are read from the app's `Info.plist` when present (so they can differ per build
/// configuration / scheme) and fall back to the documented defaults otherwise. Keep secrets OUT of
/// here — tokens live in the Keychain (``KeychainStore``), and the Claude API key never ships in the
/// app at all (it lives only on the backend, ApiSpec §9 / §14).
enum AppConfig {
    /// The App Group identifier shared by the app, widgets, and Live Activity so they read the same
    /// SwiftData store (AppSpec §7, §9). **Placeholder** — set this to match your team/bundle id and
    /// enable the matching App Groups capability on every target (see README).
    static let appGroupIdentifier = "group.app.doit"

    /// The bundle identifier used as the Sign in with Apple / APNs audience (ApiSpec §4.1, §10).
    /// **Placeholder** — replace with your real bundle id.
    static let bundleIdentifier = "app.doit.DoIT"

    /// Base URL for the DoIT API (`/api/v1`). Defaults to the documented placeholder host; override
    /// via the `DOIT_API_BASE_URL` Info.plist key per scheme (e.g. a local mock server for dev —
    /// DevelopmentPlan Phase 0 task 0.2).
    /// The live (Render-hosted) DoIT dev/staging API, co-located with Neon/Redis in Singapore.
    /// This is the default target for `-liveSync` (DevelopmentPlan P1-D). HTTPS, so no ATS exception.
    static let liveRenderBaseURL = URL(string: "https://doit-api-2clz.onrender.com/api/v1")!

    static var apiBaseURL: URL {
        #if DEBUG
        // Live-sync dev mode (`-liveSync`) targets the live Render dev API by default; pass
        // `-localApi` alongside it to hit a local stub server on :3001 instead (faster iteration).
        if isLiveSync {
            return isLocalApi ? URL(string: "http://localhost:3001/api/v1")! : liveRenderBaseURL
        }
        #endif
        if let raw = Bundle.main.object(forInfoDictionaryKey: "DOIT_API_BASE_URL") as? String,
           let url = URL(string: raw) {
            return url
        }
        // Default placeholder host (ApiSpec §3). Set your production domain at deploy.
        return URL(string: "https://doit.app/api/v1")!
    }

    /// DEBUG-only demo switch. When the app is launched with the `-uiDemo` argument, it bypasses the
    /// Sign in with Apple gate and seeds sample tasks (see ``DemoData``) so the Today shell is
    /// demoable in the simulator without a backend. Always `false` in release builds.
    static var isUIDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uiDemo")
        #else
        return false
        #endif
    }

    /// DEBUG-only: when launched with `-liveSync`, the app dev-signs-in against the local stub-enabled
    /// API (`apiBaseURL` → localhost) and runs the real offline-sync loop. Always `false` in release.
    static var isLiveSync: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-liveSync")
        #else
        return false
        #endif
    }

    /// DEBUG-only: with `-liveSync -localApi`, target a local stub server on `:3001` instead of the
    /// live Render API. Lets the same live-sync flow iterate against localhost when desired.
    static var isLocalApi: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-localApi")
        #else
        return false
        #endif
    }

    /// DEBUG-only: with `-liveSync -livePushDemo`, the app creates one task on launch via the real
    /// ``TaskCreation`` path and flushes it, proving the app→server direction end-to-end against the
    /// live API without UI automation (DevelopmentPlan P1-D). Always `false` in release.
    static var isLivePushDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-livePushDemo")
        #else
        return false
        #endif
    }

    /// DEBUG-only: with `-liveSync -liveCrudDemo`, the app creates a task then mutates it via the real
    /// ``TaskMutation`` path (complete + set priority) on launch — verifies the CRUD/update→flush path
    /// against the live API without UI automation (DevelopmentPlan P1-E). Always `false` in release.
    static var isLiveCrudDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-liveCrudDemo")
        #else
        return false
        #endif
    }

    /// DEBUG-only: with `-liveSync -liveListDemo`, the app creates a list + tag + a task assigned to
    /// both via the real ``ListMutation``/``TagMutation``/``TaskMutation`` paths on launch — verifies
    /// list/tag entities round-trip app→server (DevelopmentPlan P1-F). Always `false` in release.
    static var isLiveListDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-liveListDemo")
        #else
        return false
        #endif
    }

    /// DEBUG-only: with `-liveSync -liveQuickAddDemo`, the app parses a natural-language phrase and
    /// composes it into a task via the real quick-add path on launch (DevelopmentPlan P1-H). Always
    /// `false` in release.
    static var isLiveQuickAddDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-liveQuickAddDemo")
        #else
        return false
        #endif
    }

    /// DEBUG-only: with `-calendarDemo`, the Today dial shows sample free/busy blocks (so the EventKit
    /// overlay is screenshot-verifiable without granting calendar access). Always `false` in release.
    static var isCalendarDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-calendarDemo")
        #else
        return false
        #endif
    }

    /// DEBUG-only: with `-liveSync -liveFocusDemo`, the app logs 25 focus-minutes on one task (via the
    /// real FocusSession→actualMinutes path) and starts a live focus session for another, presenting
    /// the running timer (DevelopmentPlan P2-4). Always `false` in release.
    static var isLiveFocusDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-liveFocusDemo")
        #else
        return false
        #endif
    }

    /// DEBUG-only: with `-liveSync -liveRoutineDemo`, the app creates a daily 3-step routine and
    /// materializes today's instances on launch (DevelopmentPlan P3-3). Always `false` in release.
    static var isLiveRoutineDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-liveRoutineDemo")
        #else
        return false
        #endif
    }

    /// DEBUG-only: with `-liveSync -liveReminderDemo`, the app inserts a task + 70 reminders and runs
    /// the 64-cap scheduler on launch (DevelopmentPlan P1-I). Always `false` in release.
    static var isLiveReminderDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-liveReminderDemo")
        #else
        return false
        #endif
    }

    /// DEBUG-only: `-startTab <today|plan|lists|insights>` (or the shorthand `-startLists`) opens the
    /// app on that tab instead of Today — lets any tab be screenshot without UI navigation. Returns the
    /// tab name, or `nil` for the default. Always `nil` in release.
    static var startTab: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count { return args[i + 1] }
        if args.contains("-startLists") { return "lists" }
        return nil
        #else
        return nil
        #endif
    }
}
