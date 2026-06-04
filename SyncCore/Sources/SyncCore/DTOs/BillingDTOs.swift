import Foundation

/// The Pro entitlement the app gates features on (ApiSpec §12). Server-derived (GET /billing/status) —
/// the server validates StoreKit transactions and is the source of truth.
public struct BillingEntitlement: Codable, Sendable, Equatable {
    public var pro: Bool
    public var productId: String?
    public var expiresAt: Date?
    public var environment: String?

    public init(pro: Bool, productId: String? = nil, expiresAt: Date? = nil, environment: String? = nil) {
        self.pro = pro
        self.productId = productId
        self.expiresAt = expiresAt
        self.environment = environment
    }
}
