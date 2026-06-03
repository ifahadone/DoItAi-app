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

    private let keychain: KeychainStore
    private let idGenerator: IDGenerator
    /// Injected after init to avoid a construction cycle with ``APIClient``.
    private var apiClient: APIClient?

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
            state = .signedIn(userId: tokens.userId ?? credential.user)
        } catch {
            lastError = String(describing: error)
            // Keep prior state on failure (don't force sign-out on a transient network error).
        }
        currentNonce = nil
    }

    /// Sign out locally and drop tokens. (Server-side `POST /auth/logout` is best-effort in Phase 1.)
    func signOut() {
        // TODO(Phase 1): call POST /auth/logout to revoke this device's refresh token server-side.
        try? keychain.remove(for: KeychainStore.Account.accessToken)
        try? keychain.remove(for: KeychainStore.Account.refreshToken)
        try? keychain.remove(for: KeychainStore.Account.appleUserId)
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

    @MainActor
    private func refreshOnMain() async throws {
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
