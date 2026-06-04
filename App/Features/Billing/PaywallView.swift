import SwiftUI
import StoreKit

/// DoIT Pro paywall (AppSpec §17, DevelopmentPlan P6-4). Lists the Pro features and the subscription
/// products; purchasing is StoreKit 2 (device-bound — needs a store/sandbox account, gracefully shows
/// "unavailable" otherwise). The entitlement is server-validated.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    private var entitlements: Entitlements { services.entitlements }

    private let features: [(String, String)] = [
        ("circle.hexagongrid.fill", "The sectograph day-dial + all widgets & Live Activities"),
        ("sparkles", "AI quick-add, auto-plan, briefs & weekly reviews"),
        ("calendar.badge.plus", "Apple Calendar write-back"),
        ("chart.bar.fill", "Full analytics dashboards"),
        ("repeat", "Unlimited routines & habits"),
        ("person.2.fill", "Sharing & multi-device sync"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                if entitlements.isPro {
                    Section {
                        Label("You're on DoIT Pro", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        if let expires = entitlements.expiresAt {
                            LabeledContent("Renews", value: expires.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }

                Section("DoIT Pro") {
                    ForEach(features, id: \.1) { icon, text in
                        Label(text, systemImage: icon)
                    }
                }

                if !entitlements.isPro {
                    Section {
                        if entitlements.products.isEmpty {
                            Text("Subscription options are unavailable here. They appear on a device signed in to the App Store.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            ForEach(entitlements.products, id: \.id) { product in
                                Button {
                                    Task { await entitlements.purchase(product); if entitlements.isPro { dismiss() } }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(product.displayName)
                                            Text(product.description).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(product.displayPrice).fontWeight(.semibold)
                                    }
                                }
                                .disabled(entitlements.purchasing)
                            }
                        }
                        Button("Restore purchases") { Task { await entitlements.restore() } }
                    } footer: {
                        Text("Subscriptions renew automatically until canceled. Your purchase is validated by the DoIT backend.")
                    }
                }
            }
            .navigationTitle("DoIT Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await entitlements.loadProducts() }
        }
    }
}
