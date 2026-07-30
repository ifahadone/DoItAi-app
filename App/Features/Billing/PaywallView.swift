import SwiftUI
import StoreKit
import DesignSystem

/// A benefit-first StoreKit 2 paywall. The quick decision is visible before the feature details,
/// while restore, renewal, and server-validation information remain easy to find.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(AppServices.self) private var services

    private var entitlements: Entitlements { services.entitlements }

    private let features: [(String, String, String)] = [
        ("circle.hexagongrid.fill", "See the whole day", "Sectograph, widgets and Live Activities"),
        ("sparkles", "Plan with less effort", "AI capture, auto-plan, briefs and weekly reviews"),
        ("chart.bar.fill", "Learn what works", "Full trends, routines and habit insights"),
        ("person.2.fill", "Keep everything together", "Calendar write-back, sharing and multi-device sync"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.xl) {
                    hero
                        .doitEntrance()

                    if entitlements.isPro {
                        proStatus
                            .doitEntrance(order: 1)
                    } else {
                        purchaseOptions
                            .doitEntrance(order: 1)
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.lg) {
                        DoITSectionHeading(
                            "Everything in Pro",
                            subtitle: "Extra depth when you need it. The everyday flow stays simple."
                        )
                        ForEach(Array(features.enumerated()), id: \.element.1) { index, feature in
                            featureRow(icon: feature.0, title: feature.1, detail: feature.2)
                                .doitEntrance(order: index + 2)
                        }
                    }

                    Text("Subscriptions renew automatically until canceled. Purchases are validated by the DoIT backend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(theme.spacing.lg)
            }
            .navigationTitle("DoIT Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await entitlements.loadProducts() }
            .animation(.spring(response: 0.38, dampingFraction: 0.9), value: entitlements.isPro)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
                .symbolEffect(.pulse)
            Text(entitlements.isPro ? "Your full day, unlocked." : "Do more. Tap less.")
                .font(.largeTitle.bold())
            Text("Pro adds deeper planning and insight without adding friction to your day.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var proStatus: some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're on DoIT Pro").font(.headline)
                if let expires = entitlements.expiresAt {
                    Text("Renews \(expires.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(theme.spacing.lg)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.large))
    }

    @ViewBuilder
    private var purchaseOptions: some View {
        VStack(spacing: theme.spacing.sm) {
            if entitlements.products.isEmpty {
                Label(
                    "Plans appear on a device signed in to the App Store.",
                    systemImage: "info.circle"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.lg)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.large))
            } else {
                ForEach(entitlements.products, id: \.id) { product in
                    Button {
                        Task {
                            await entitlements.purchase(product)
                            if entitlements.isPro { dismiss() }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(product.displayName).font(.headline)
                                Text(product.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Text(product.displayPrice).font(.headline)
                        }
                        .padding(theme.spacing.lg)
                        .background(theme.colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: theme.radii.large))
                    }
                    .buttonStyle(.plain)
                    .disabled(entitlements.purchasing)
                }
            }

            Button("Restore purchases") {
                Task { await entitlements.restore() }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, theme.spacing.xs)

            if entitlements.purchasing {
                ProgressView("Completing purchase…")
                    .transition(.opacity)
            }
            if let error = entitlements.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(theme.colors.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
