import SwiftUI

/// Environment plumbing so any view can read the active ``Theme`` via `@Environment(\.theme)`
/// (AppSpec §11 "consumed via SwiftUI Environment").
private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Theme = .default
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

public extension View {
    /// Inject a ``Theme`` into the environment for this view subtree.
    func theme(_ theme: Theme) -> some View {
        environment(\.theme, theme)
    }
}
