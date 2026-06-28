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

    /// Presents the local-first explanation before committing to device-only mode (G01-S04).
    @State private var showLocalExplain = false

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
            .disabled(auth.isSigningIn)

            // Local-first account choice (G01-S02): use DoIT device-only, no cloud account.
            Button {
                showLocalExplain = true
            } label: {
                Text("Continue without an account")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, theme.spacing.xl)
            .accessibilityIdentifier("continueLocallyButton")
            .disabled(auth.isSigningIn)

            if auth.isSigningIn {
                VStack(spacing: 4) {
                    ProgressView()
                    Text("Connecting… the server may take a moment to wake up.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, theme.spacing.xl)
            } else if let error = auth.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(theme.colors.statusOverdue)
                    .multilineTextAlignment(.center)
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
            .disabled(auth.isSigningIn)
            #endif

            Spacer().frame(height: theme.spacing.xxl)
        }
        .padding()
        .sheet(isPresented: $showLocalExplain) {
            LocalFirstExplanationView(
                onContinue: { showLocalExplain = false; auth.continueLocally() },
                onSignIn: { showLocalExplain = false; Task { await auth.signInWithApple() } }
            )
            .presentationDetents([.medium, .large])
        }
    }
}

/// Local-First Mode Explanation (journey G01-S04): what device-only mode means before the user
/// commits — data stays on this device, no sync across devices, and an account can be added later.
private struct LocalFirstExplanationView: View {
    @Environment(\.theme) private var theme
    let onContinue: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 44)).foregroundStyle(theme.colors.accent)
                Text("Use DoIT on this device").font(.title2.bold())
                Text("No account needed. Your tasks, routines and notes live only on this iPhone.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, theme.spacing.lg)

            VStack(alignment: .leading, spacing: theme.spacing.md) {
                point("checkmark.shield", "Private by default", "Nothing leaves your device unless you turn on AI or sign in.")
                point("arrow.triangle.2.circlepath", "No cross-device sync", "Without an account, data won't sync to other devices or back up to the cloud.")
                point("person.crop.circle.badge.plus", "Upgrade anytime", "Sign in with Apple later to keep your data and sync everywhere.")
            }

            Spacer(minLength: 0)

            VStack(spacing: theme.spacing.sm) {
                Button(action: onContinue) {
                    Text("Continue on this device")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("confirmLocalModeButton")
                Button(action: onSignIn) {
                    Text("Sign in with Apple instead")
                        .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private func point(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            Image(systemName: icon).foregroundStyle(theme.colors.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
