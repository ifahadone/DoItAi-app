import Foundation
import StoreKit
import SyncCore

/// The single Pro-entitlement gate (AppSpec §17, DevelopmentPlan P6-4). The SERVER is the source of
/// truth (`GET /billing/status`, validated StoreKit transactions); this mirrors it and drives the
/// StoreKit 2 purchase flow.
///
/// **Device-bound:** loading products + purchasing needs a real App Store / sandbox account (or a
/// StoreKit configuration file in the scheme). In the simulator without one, `products` is empty and
/// purchase is a no-op — the entitlement still reflects the server, and every Pro gate degrades to
/// "not Pro" safely.
@MainActor
@Observable
final class Entitlements {
    static let productIDs = ["app.doit.pro.monthly", "app.doit.pro.annual"]

    private let apiClient: APIClient

    private(set) var isPro = false
    private(set) var expiresAt: Date?
    private(set) var products: [Product] = []
    private(set) var purchasing = false
    /// Surfaced to the paywall when a purchase completes but the server confirmation fails.
    private(set) var lastError: String?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Refresh the entitlement from the server (the authority). Best-effort.
    func refresh() async {
        if let status = try? await apiClient.billingStatus() {
            isPro = status.pro
            expiresAt = status.expiresAt
        }
    }

    /// Load purchasable products (device-bound; empty without a store/config).
    func loadProducts() async {
        products = (try? await Product.products(for: Self.productIDs)) ?? []
    }

    /// Purchase a product, submit the signed transaction to the server, then re-read the entitlement.
    /// Returns whether the user is Pro afterward.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchasing = true
        lastError = nil
        defer { purchasing = false }
        guard let result = try? await product.purchase() else { return isPro }
        if case let .success(verification) = result {
            // The JWS (server verifies it) lives on the VerificationResult, not the Transaction.
            do {
                _ = try await apiClient.submitReceipt(verification.jwsRepresentation)
            } catch {
                // A paid purchase that fails to record server-side is a real support issue — surface it.
                lastError = "Purchase succeeded but couldn't be confirmed. It'll be restored when you're back online."
                #if DEBUG
                print("⚠️ Receipt submission failed after purchase: \(error)")
                #endif
            }
            if case let .verified(transaction) = verification { await transaction.finish() }
            await refresh()
        }
        return isPro
    }

    /// Restore: re-submit current entitlements to the server, then refresh.
    func restore() async {
        for await result in Transaction.currentEntitlements {
            do {
                _ = try await apiClient.submitReceipt(result.jwsRepresentation)
            } catch {
                #if DEBUG
                print("⚠️ Restore: receipt submission failed for one transaction: \(error)")
                #endif
            }
        }
        await refresh()
    }
}
