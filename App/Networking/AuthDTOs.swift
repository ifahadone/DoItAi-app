import Foundation

// Auth request/response shapes for `/auth/*` (ApiSpec §4, §7.1). These live in the app's Networking
// layer (not SyncCore) because they're transport/identity concerns, not the synced data contract.

/// Body for `POST /auth/apple` (ApiSpec §4.1).
struct AppleSignInRequest: Codable, Sendable {
    let identityToken: String
    let authorizationCode: String
    let nonce: String
    let deviceInfo: DeviceInfo

    struct DeviceInfo: Codable, Sendable {
        var platform: String = "ios"
        var appVersion: String?
        /// Client device id (UUID string), bound to issued tokens for per-device revocation.
        var deviceId: String
    }
}

/// Token pair returned by `/auth/apple` and `/auth/refresh` (ApiSpec §4.2).
struct TokenPair: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    /// Access token lifetime in seconds (ApiSpec §4.2: 15 min).
    let expiresIn: Int?
    /// Echoed Apple `sub` / our user id when present.
    let userId: String?
}

/// Body for `POST /auth/refresh` (ApiSpec §4.2 — opaque refresh token in body).
struct RefreshRequest: Codable, Sendable {
    let refreshToken: String
}

/// The standard error envelope (ApiSpec §3 / §21). Decoded to surface a machine-readable `code`.
struct APIErrorEnvelope: Codable, Sendable {
    struct Body: Codable, Sendable {
        let code: String
        let message: String
        let requestId: String?
    }
    let error: Body
}
