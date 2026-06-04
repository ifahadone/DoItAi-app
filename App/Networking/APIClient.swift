import Foundation
import SyncCore

/// Async HTTP client for the DoIT API (AppSpec §7, ApiSpec §3–§7).
///
/// An `actor` (concurrency-safe per AppSpec §7) over `URLSession`. It attaches the `Bearer` access
/// token and the required headers (`Idempotency-Key`, `X-Client-Version`, `X-Request-Id`) and decodes
/// the standard error envelope. Conforms to ``SyncTransport`` so the ``DefaultSyncEngine`` flushes
/// through it without SyncCore importing URLSession.
///
/// Token handling is delegated to an injected ``TokenProviding`` (backed by ``AuthService`` /
/// ``KeychainStore``) so this client stays free of auth/storage policy. On a `401` it asks the
/// provider to refresh once and retries.
///
/// Requires the Xcode app target (uses `URLSession`/`Bundle.main`). Not built by the SPM packages.
actor APIClient: SyncTransport {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: TokenProviding
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let clientVersion: String

    init(
        baseURL: URL = AppConfig.apiBaseURL,
        session: URLSession = .shared,
        tokenProvider: TokenProviding,
        clientVersion: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.encoder = JSONCoding.makeEncoder()
        self.decoder = JSONCoding.makeDecoder()
        self.clientVersion = clientVersion
    }

    // MARK: - Errors

    enum APIError: Error {
        /// A structured error returned by the server (`code` from ApiSpec §21).
        case server(status: Int, code: String, message: String, requestId: String?)
        /// A non-2xx response that did not carry the standard envelope.
        case http(status: Int, body: Data)
        case unauthenticated
        case invalidResponse
    }

    // MARK: - Auth endpoints (ApiSpec §4)

    /// `POST /auth/apple` — exchange the Apple identity token for our token pair. Unauthenticated.
    func signInWithApple(_ request: AppleSignInRequest) async throws -> TokenPair {
        try await send(
            method: "POST",
            path: "auth/apple",
            body: request,
            authenticated: false,
            idempotent: true
        )
    }

    /// `POST /auth/refresh` — rotate the access/refresh pair. Unauthenticated (refresh token in body).
    func refresh(_ request: RefreshRequest) async throws -> TokenPair {
        try await send(
            method: "POST",
            path: "auth/refresh",
            body: request,
            authenticated: false,
            idempotent: true
        )
    }

    // MARK: - Sync endpoints (ApiSpec §6) / SyncTransport conformance

    /// `POST /sync/push` — flush a batch of outbox ops.
    func syncPush(_ request: SyncPushRequest) async throws -> SyncPushResponse {
        try await send(method: "POST", path: "sync/push", body: request, authenticated: true, idempotent: true)
    }

    /// `GET /sync/pull?cursor=…&limit=…` — fetch deltas since the cursor.
    func syncPull(cursor: String?, limit: Int = 500) async throws -> SyncPullResponse {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(
            method: "GET",
            path: "sync/pull",
            queryItems: items,
            bodyData: nil,
            authenticated: true,
            idempotent: false
        )
    }

    // SyncTransport conformance — thin aliases so the engine can depend on the protocol.
    func push(_ request: SyncPushRequest) async throws -> SyncPushResponse {
        try await syncPush(request)
    }

    func pull(cursor: String?, limit: Int) async throws -> SyncPullResponse {
        try await syncPull(cursor: cursor, limit: limit)
    }

    /// `POST /habits/{id}/log` — record a habit completion; the server recomputes the streak
    /// authoritatively and returns the updated routine (DevelopmentPlan P3-2/P3-4).
    func logHabit(routineId: String, date: String) async throws -> RoutineDTO {
        struct LogBody: Encodable, Sendable { let date: String }
        struct LogResponse: Decodable { let routine: RoutineDTO }
        let response: LogResponse = try await send(
            method: "POST", path: "habits/\(routineId)/log",
            body: LogBody(date: date), authenticated: true, idempotent: true
        )
        return response.routine
    }

    // MARK: - AI proxy (Phase 4, ApiSpec §9). All throw on 403 ai_consent_required / 429 budget /
    // 503 ai_unavailable so callers fall back to the on-device/rules path.

    func aiConsent() async throws -> Bool {
        struct R: Decodable { let aiConsent: Bool }
        let r: R = try await send(method: "GET", path: "ai/consent", bodyData: nil, authenticated: true, idempotent: false)
        return r.aiConsent
    }

    @discardableResult
    func setAiConsent(_ consent: Bool) async throws -> Bool {
        struct Body: Encodable, Sendable { let consent: Bool }
        struct R: Decodable { let aiConsent: Bool }
        let r: R = try await send(method: "POST", path: "ai/consent", body: Body(consent: consent), authenticated: true, idempotent: false)
        return r.aiConsent
    }

    func aiParse(_ request: AIParseRequest) async throws -> AIParsedTask {
        let r: AIParseResponse = try await send(method: "POST", path: "ai/parse", body: request, authenticated: true, idempotent: false)
        return r.task
    }

    func aiSchedule(_ request: AIScheduleRequest) async throws -> AIScheduleProposal {
        try await send(method: "POST", path: "ai/schedule", body: request, authenticated: true, idempotent: false)
    }

    func aiSearch(_ request: AISearchRequest) async throws -> AISearchFilter {
        let r: AISearchResponse = try await send(method: "POST", path: "ai/search", body: request, authenticated: true, idempotent: false)
        return r.filter
    }

    func aiRoutineSuggest(_ request: AIRoutineSuggestRequest) async throws -> [AIRoutineSuggestion] {
        let r: AIRoutineSuggestions = try await send(method: "POST", path: "ai/routine-suggest", body: request, authenticated: true, idempotent: false)
        return r.suggestions
    }

    /// Stream a morning brief as SSE narrative events (ApiSpec §9.5).
    func aiBriefStream(_ request: AIBriefRequest) -> AsyncThrowingStream<AINarrativeEvent, Error> {
        streamNarrative(path: "ai/brief", body: request)
    }

    /// Stream a weekly review as SSE narrative events.
    func aiReviewStream(_ request: AIReviewRequest) -> AsyncThrowingStream<AINarrativeEvent, Error> {
        streamNarrative(path: "ai/review", body: request)
    }

    private func streamNarrative<Body: Encodable & Sendable>(path: String, body: Body) -> AsyncThrowingStream<AINarrativeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runSSE(path: path, body: body) { event in continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runSSE<Body: Encodable & Sendable>(
        path: String, body: Body, onEvent: @Sendable (AINarrativeEvent) -> Void
    ) async throws {
        let data = try encoder.encode(body)
        var request = try await makeRequest(
            method: "POST", path: path, queryItems: [], bodyData: data, authenticated: true, idempotent: false
        )
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: Data())
        }
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            if let event = AINarrativeEvent.parse(dataPayload: String(line.dropFirst(6))) {
                onEvent(event)
                if case .done = event { break }
            }
        }
    }

    // MARK: - Billing (Phase 6, ApiSpec §12). The server validates StoreKit transactions.

    func billingStatus() async throws -> BillingEntitlement {
        try await send(method: "GET", path: "billing/status", bodyData: nil, authenticated: true, idempotent: false)
    }

    @discardableResult
    func submitReceipt(_ signedTransaction: String) async throws -> BillingEntitlement {
        struct Body: Encodable, Sendable { let signedTransaction: String }
        return try await send(method: "POST", path: "billing/receipt",
                              body: Body(signedTransaction: signedTransaction), authenticated: true, idempotent: false)
    }

    // MARK: - Account (Phase 6, ApiSpec §11). Data portability + deletion.

    /// Fetch the full data-export bundle as raw JSON bytes (for a share sheet / file).
    func exportAccountData() async throws -> Data {
        let request = try await makeRequest(method: "POST", path: "account/export", queryItems: [],
                                            bodyData: nil, authenticated: true, idempotent: false)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        return data
    }

    /// Permanently delete the account + all its data (204).
    func deleteAccount() async throws {
        let _: EmptyResponse = try await send(method: "DELETE", path: "account", bodyData: nil,
                                              authenticated: true, idempotent: false)
    }

    // MARK: - Core request pipeline

    /// Encode `body` (if any) and delegate to the data-based sender. The typed entry point used by
    /// the endpoints with a JSON request body.
    private func send<Body: Encodable & Sendable, Response: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        authenticated: Bool,
        idempotent: Bool
    ) async throws -> Response {
        let data = try encoder.encode(body)
        return try await send(
            method: method, path: path, queryItems: queryItems,
            bodyData: data, authenticated: authenticated, idempotent: idempotent
        )
    }

    /// Build, send, and decode a request, retrying once on `401` after a token refresh. Works with a
    /// pre-encoded body (or `nil` for bodyless GETs) so there is no need for an `Encodable` over
    /// `Never`.
    private func send<Response: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        bodyData: Data?,
        authenticated: Bool,
        idempotent: Bool
    ) async throws -> Response {
        let request = try await makeRequest(
            method: method, path: path, queryItems: queryItems,
            bodyData: bodyData, authenticated: authenticated, idempotent: idempotent
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401, authenticated {
            // TODO(Phase 1): de-dupe concurrent refreshes (single-flight) so a burst of 401s triggers
            //   exactly one refresh. For Phase 0 we refresh-and-retry once.
            try await tokenProvider.refreshTokens()
            let retried = try await makeRequest(
                method: method, path: path, queryItems: queryItems,
                bodyData: bodyData, authenticated: authenticated, idempotent: idempotent
            )
            let (retryData, retryResponse) = try await session.data(for: retried)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else { throw APIError.invalidResponse }
            return try decodeResponse(data: retryData, http: retryHTTP)
        }

        return try decodeResponse(data: data, http: http)
    }

    private func makeRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        authenticated: Bool,
        idempotent: Bool
    ) async throws -> URLRequest {
        // Resolve the full URL: baseURL already ends in /api/v1; append the path.
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30 // every external call needs a timeout (global rule)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(clientVersion, forHTTPHeaderField: "X-Client-Version")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")

        // Idempotency-Key on every non-GET mutation so retried flushes are safe (ApiSpec §3, §6.3).
        if idempotent, method != "GET" {
            request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        }

        if authenticated {
            guard let token = try await tokenProvider.currentAccessToken() else {
                throw APIError.unauthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = bodyData
        return request
    }

    private func decodeResponse<Response: Decodable>(data: Data, http: HTTPURLResponse) throws -> Response {
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                throw APIError.server(
                    status: http.statusCode,
                    code: envelope.error.code,
                    message: envelope.error.message,
                    requestId: envelope.error.requestId
                )
            }
            throw APIError.http(status: http.statusCode, body: data)
        }

        // 204 No Content with a decodable expecting a value: only valid when Response is optional.
        if data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }
        return try decoder.decode(Response.self, from: data)
    }
}

/// Placeholder for endpoints that return `204 No Content`.
struct EmptyResponse: Decodable, Sendable {}

/// Supplies the current access token and can refresh it. Implemented by ``AuthService``.
///
/// Modeled as a protocol so ``APIClient`` doesn't depend on Keychain/auth specifics and can be
/// unit-tested with a stub.
protocol TokenProviding: Sendable {
    /// The current access token, or `nil` if signed out.
    func currentAccessToken() async throws -> String?
    /// Rotate tokens (used on a 401). Throws if refresh fails (caller should sign the user out).
    func refreshTokens() async throws
}
