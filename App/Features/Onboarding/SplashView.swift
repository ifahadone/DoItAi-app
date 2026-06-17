import SwiftUI
import DesignSystem

/// Branded boot surface (AppSpec S01) shown while ``AuthService`` bootstraps auth/entitlement/local
/// state. Intentionally thin and non-blocking — it replaces a bare `ProgressView` so the cold-launch
/// moment reads as DoIT rather than a system spinner. Sync/offline issues surface later via the
/// in-app banner, not here.
struct SplashView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            VStack(spacing: theme.spacing.lg) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(theme.colors.accent)
                Text("DoIT")
                    .font(.largeTitle.bold())
                ProgressView()
                    .padding(.top, theme.spacing.sm)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DoIT, loading")
    }
}
