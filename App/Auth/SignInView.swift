import SwiftUI
import DesignSystem

/// The sign-in gate (AppSpec §13, ApiSpec §4.1). Sign in with Apple is the only identity provider at
/// launch. Tapping the button drives ``AuthService/signInWithApple()``, which presents the Apple
/// authorization sheet (configuring the nonce + scopes internally), exchanges the credential at
/// `POST /auth/apple`, and stores the returned tokens in the Keychain.
///
/// Requires the Xcode app target + the "Sign in with Apple" capability (see README).
struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer()

            VStack(spacing: theme.spacing.md) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(theme.colors.accent)
                Text("DoIT")
                    .font(.largeTitle.bold())
                Text("Plan, execute, and reflect on your day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // DoIT routes the entire Sign in with Apple flow — request, presentation, and the
            // `/auth/apple` exchange — through `AuthService` so it's testable and owns token storage.
            // We therefore use a button styled to match Apple's, rather than `SignInWithAppleButton`,
            // to avoid the native button presenting its *own* second authorization controller.
            // (`AuthService.prepareRequest(_:)` is still public for callers who prefer the native
            // button and want to drive the controller themselves.)
            Button {
                Task { await auth.signInWithApple() }
            } label: {
                Label("Sign in with Apple", systemImage: "applelogo")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(colorScheme == .dark ? .white : .black)
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .padding(.horizontal, theme.spacing.xl)
            .accessibilityIdentifier("signInWithAppleButton")

            if let error = auth.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(theme.colors.statusOverdue)
                    .padding(.horizontal, theme.spacing.xl)
            }

            #if DEBUG
            // Developer sign-in: skips the Apple capability by minting a stub identity token the dev
            // backend (`APPLE_STUB_VERIFICATION=true`) decodes without verifying. Never in release.
            Button {
                Task { await auth.devSignIn() }
            } label: {
                Label("Developer sign-in", systemImage: "hammer.fill")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, theme.spacing.xl)
            .accessibilityIdentifier("devSignInButton")
            #endif

            Spacer().frame(height: theme.spacing.xxl)
        }
        .padding()
    }
}
