import Foundation
import AuthenticationServices
import CryptoKit
import UIKit
import SyncCore

/// Owns the user's authentication state and tokens (AppSpec §13, ApiSpec §4).
///
/// Responsibilities:
/// - run Sign in with Apple (`AuthenticationServices`) and exchange the Apple credential at
///   `POST /auth/apple`,
/// - persist the resulting token pair in the Keychain (``KeychainStore``),
/// - vend the current access token and refresh it on demand (``TokenProviding``) for ``APIClient``.
///
/// `@Observable` + `@MainActor` so SwiftUI can bind to `state` for the auth gate; the actual token
/// I/O is delegated to the `Sendable` ``KeychainStore``. The `APIClient` is injected lazily to break
/// the cycle (APIClient needs a TokenProviding; AuthService needs an APIClient to refresh).
///
/// Requires the Xcode app target (links `AuthenticationServices`).
@Observable
@MainActor
final class AuthService: NSObject, TokenProviding {
    enum State: Equatable {
        case unknown          // not yet checked Keychain
        case signedOut
        case signedIn(userId: String?)
    }

    private(set) var state: State = .unknown
    /// Set when a sign-in attempt fails, for surfacing in the UI.
    private(set) var lastError: String?
    /// True while a sign-in network exchange is in flight, so the UI can show a spinner + disable the
    /// buttons (the dev backend may cold-start for ~30–50s).
    private(set) var isSigningIn = false

    private let keychain: KeychainStore
    private let idGenerator: IDGenerator
    /// Injected after init to avoid a construction cycle with ``APIClient``.
    private var apiClient: APIClient?

    /// UserDefaults flag marking a local-first session (journey G01-S02/S04, US-ONB-020): the user
    /// chose to use DoIT device-only, without a cloud account. Restored on launch by ``bootstrap()``.
    private static let localModeKey = "doit.auth.localMode"
    /// True when the user is using DoIT in local-first (device-only) mode.
    var isLocalMode: Bool { UserDefaults.standard.bool(forKey: Self.localModeKey) }

    /// The nonce for the in-flight Sign in with Apple request (replay protection, ApiSpec §4.1).
    private var currentNonce: String?
    /// Continuation bridging the delegate callback into async/await.
    private var signInContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    init(keychain: KeychainStore = KeychainStore(), idGenerator: IDGenerator = UUIDGenerator()) {
        self.keychain = keychain
        self.idGenerator = idGenerator
        super.init()
    }

    /// Wire the API client (call once at app startup after both are constructed).
    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Session bootstrap

    /// Decide the initial state from the Keychain (call on launch).
    func bootstrap() async {
        #if DEBUG
        // Demo mode (`-uiDemo`): skip the Apple gate so the shell is reachable without a backend.
        if AppConfig.isUIDemo {
            state = .signedIn(userId: "demo-user")
            return
        }
        // Live-sync dev mode (`-liveSync`): dev sign-in against the local stub API, then sync for real.
        if AppConfig.isLiveSync {
            await devSignIn()
            return
        }
        #endif
        // Local-first session (chosen at the account gate): no tokens, device-only, owner = nil.
        if isLocalMode {
            state = .signedIn(userId: nil)
            return
        }
        do {
            if let _ = try keychain.string(for: KeychainStore.Account.refreshToken) {
                let userId = try keychain.string(for: KeychainStore.Account.appleUserId)
                state = .signedIn(userId: userId)
            } else {
                state = .signedOut
            }
        } catch {
            state = .signedOut
        }
    }

    /// Enter local-first (device-only) mode (journey G01-S02/S04). No network, no account; data lives
    /// on this device and can be upgraded to a cloud account later via Sign in with Apple.
    func continueLocally() {
        lastError = nil
        UserDefaults.standard.set(true, forKey: Self.localModeKey)
        state = .signedIn(userId: nil)
    }

    #if DEBUG
    /// DEBUG dev sign-in for `-liveSync`: mint an unsigned, decodable stub Apple identity token (the
    /// server's `APPLE_STUB_VERIFICATION` decodes it WITHOUT verifying and trusts `sub`) and exchange
    /// it at `POST /auth/apple` for real tokens — so the simulator can drive the live sync loop
    /// without the Sign in with Apple capability. Never compiled into release.
    func devSignIn() async {
        lastError = nil
        isSigningIn = true
        defer { isSigningIn = false }
        guard let apiClient else { state = .signedOut; return }
        let sub = "ios-dev-user"
        let request = AppleSignInRequest(
            identityToken: Self.makeStubIdentityToken(sub: sub),
            authorizationCode: "dev",
            nonce: "dev",
            deviceInfo: .init(appVersion: "dev", deviceId: idGenerator.newID())
        )
        do {
            let tokens = try await apiClient.signInWithApple(request)
            try persist(tokens, appleUserId: sub)
            UserDefaults.standard.set(false, forKey: Self.localModeKey)
            state = .signedIn(userId: tokens.userId ?? sub)
        } catch {
            lastError = "dev sign-in failed: \(error)"
            state = .signedOut
        }
    }

    /// Build an UNSIGNED, structurally-valid JWT carrying `sub` (for the server dev stub only).
    static func makeStubIdentityToken(sub: String) -> String {
        func b64url(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = b64url(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let now = Int(Date().timeIntervalSince1970)
        let payload = b64url(Data(#"{"sub":"\#(sub)","email":"\#(sub)@doit.app","iat":\#(now),"exp":\#(now + 3600)}"#.utf8))
        let sig = b64url(Data("devsig".utf8))
        return "\(header).\(payload).\(sig)"
    }
    #endif

    // MARK: - Sign in with Apple

    /// Configure an `ASAuthorizationAppleIDRequest` (call from the SignInWithAppleButton handler).
    func prepareRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        // Apple hashes the raw nonce; the server verifies the hash against the identity token.
        request.nonce = Self.sha256(nonce)
    }

    /// Drive the full flow: present Apple sheet → exchange at the API → persist tokens.
    func signInWithApple() async {
        lastError = nil
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let credential = try await requestAppleCredential()
            guard
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8),
                let codeData = credential.authorizationCode,
                let authorizationCode = String(data: codeData, encoding: .utf8),
                let nonce = currentNonce
            else {
                throw AuthError.missingAppleCredential
            }

            guard let apiClient else { throw AuthError.notConfigured }

            let request = AppleSignInRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                nonce: nonce,
                deviceInfo: .init(
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                    deviceId: idGenerator.newID()
                )
            )

            let tokens = try await apiClient.signInWithApple(request)
            try persist(tokens, appleUserId: credential.user)
            UserDefaults.standard.set(false, forKey: Self.localModeKey) // upgraded local → cloud
            state = .signedIn(userId: tokens.userId ?? credential.user)
        } catch {
            lastError = String(describing: error)
            // Keep prior state on failure (don't force sign-out on a transient network error).
        }
        currentNonce = nil
    }

    /// Sign out: best-effort server-side refresh-token revoke, then drop local tokens + state.
    func signOut() {
        // Revoke this device's refresh token server-side before clearing it (idempotent; ignored when
        // offline / on failure). Captured before removal so the in-flight call still has a valid token.
        if let refresh = try? keychain.string(for: KeychainStore.Account.refreshToken), let apiClient {
            Task { try? await apiClient.logout(refreshToken: refresh) }
        }
        try? keychain.remove(for: KeychainStore.Account.accessToken)
        try? keychain.remove(for: KeychainStore.Account.refreshToken)
        try? keychain.remove(for: KeychainStore.Account.appleUserId)
        UserDefaults.standard.set(false, forKey: Self.localModeKey)
        state = .signedOut
    }

    // MARK: - TokenProviding (used by APIClient)

    nonisolated func currentAccessToken() async throws -> String? {
        try await MainActor.run {
            try keychain.string(for: KeychainStore.Account.accessToken)
        }
    }

    nonisolated func refreshTokens() async throws {
        try await refreshOnMain()
    }

    /// A single in-flight token refresh, so a burst of concurrent 401s coalesces into ONE refresh
    /// instead of each thrashing the rotating refresh token (which would trip reuse-detection).
    private var refreshTask: Task<Void, Error>?

    @MainActor
    private func refreshOnMain() async throws {
        // Coalesce onto an in-flight refresh if one is already running (single-flight).
        if let existing = refreshTask {
            try await existing.value
            return
        }
        let task = Task<Void, Error> { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    @MainActor
    private func performRefresh() async throws {
        guard let apiClient else { throw AuthError.notConfigured }
        guard let refreshToken = try keychain.string(for: KeychainStore.Account.refreshToken) else {
            state = .signedOut
            throw AuthError.notSignedIn
        }
        do {
            let tokens = try await apiClient.refresh(RefreshRequest(refreshToken: refreshToken))
            try persist(tokens, appleUserId: try keychain.string(for: KeychainStore.Account.appleUserId))
        } catch {
            // Refresh failure (e.g. reuse-detected/expired) ⇒ force re-auth (ApiSpec §4.2).
            signOut()
            throw error
        }
    }

    // MARK: - Persistence

    private func persist(_ tokens: TokenPair, appleUserId: String?) throws {
        try keychain.set(tokens.accessToken, for: KeychainStore.Account.accessToken)
        try keychain.set(tokens.refreshToken, for: KeychainStore.Account.refreshToken)
        if let appleUserId, !appleUserId.isEmpty {
            try keychain.set(appleUserId, for: KeychainStore.Account.appleUserId)
        }
    }

    // MARK: - Apple delegate bridge

    private func requestAppleCredential() async throws -> ASAuthorizationAppleIDCredential {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        prepareRequest(request)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            controller.performRequests()
        }
    }

    enum AuthError: Error {
        case missingAppleCredential
        case notConfigured
        case notSignedIn
    }
}

// MARK: - ASAuthorizationController delegate / presentation

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                self.signInContinuation?.resume(throwing: AuthError.missingAppleCredential)
                self.signInContinuation = nil
                return
            }
            self.signInContinuation?.resume(returning: credential)
            self.signInContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.signInContinuation?.resume(throwing: error)
            self.signInContinuation = nil
        }
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the app's key window. Safe on the main actor in practice; resolved synchronously
        // by AuthenticationServices on the main thread.
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Nonce / hashing helpers (ApiSpec §4.1)

private extension AuthService {
    /// A cryptographically-random nonce string for Sign in with Apple replay protection.
    static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess, "Unable to generate secure random nonce")
            for random in randoms where remaining > 0 {
                if random < UInt8(charset.count) {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// SHA-256 hex digest of `input` (Apple expects the hashed nonce on the request).
    static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
