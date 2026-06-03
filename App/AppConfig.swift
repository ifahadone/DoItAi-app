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
    static var apiBaseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "DOIT_API_BASE_URL") as? String,
           let url = URL(string: raw) {
            return url
        }
        // Default placeholder host (ApiSpec §3). Set your production domain at deploy.
        return URL(string: "https://doit.app/api/v1")!
    }
}
