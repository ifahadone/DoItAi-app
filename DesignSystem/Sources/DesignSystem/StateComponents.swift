import SwiftUI

/// Reusable cross-cutting **state components** that align the app with the Figma state-variant frames
/// (journey G16 + the per-journey empty/offline/conflict/permission/error/undo states). Implementing
/// these once as a shared family — rather than as ~130 one-off screens — is the design-system-correct
/// way to "complete against Figma": every journey shows the same offline banner, conflict resolver,
/// permission card, Pro gate, loading skeleton, error view and undo toast.
///
/// All are pure, dependency-free SwiftUI so they work in any view, the widgets, and previews.

private func sc(_ h: String, _ fb: Color = .gray) -> Color { Color(hex: h) ?? fb }
private enum SCPalette {
    static let accent = sc("#2E7DF6", .blue)
    static let label = sc("#1C1C1E", .primary)
    static let secondary = sc("#8E8E93", .secondary)
    static let card = sc("#FFFFFF", .white)
    static let success = sc("#34C759", .green)
    static let warning = sc("#FF9F0A", .orange)
    static let danger = sc("#FF453A", .red)
}

// MARK: - Status banner (offline / syncing / retrying / failed) — G16-S01…S04, G02-S09

public struct StatusBanner: View {
    public enum Kind: Sendable { case offline, syncing, retrying, failed, info, success }
    private let kind: Kind
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(_ kind: Kind, _ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.kind = kind; self.message = message; self.actionTitle = actionTitle; self.action = action
    }

    private var tint: Color {
        switch kind {
        case .offline, .retrying, .info: return SCPalette.accent
        case .syncing: return SCPalette.secondary
        case .failed: return SCPalette.danger
        case .success: return SCPalette.success
        }
    }
    private var icon: String {
        switch kind {
        case .offline: return "wifi.slash"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .retrying: return "arrow.clockwise"
        case .failed: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    public var body: some View {
        HStack(spacing: 10) {
            if kind == .syncing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon).foregroundStyle(tint)
            }
            Text(message).font(.footnote).foregroundStyle(SCPalette.label)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.footnote.weight(.semibold)).foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.25)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Undo toast — G16-S13, G02-S10, G03-S09

public struct UndoToast: View {
    private let message: String
    private let undoTitle: String
    private let onUndo: () -> Void

    public init(_ message: String, undoTitle: String = "Undo", onUndo: @escaping () -> Void) {
        self.message = message; self.undoTitle = undoTitle; self.onUndo = onUndo
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(SCPalette.success)
            Text(message).font(.subheadline).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(undoTitle, action: onUndo)
                .font(.subheadline.weight(.semibold)).foregroundStyle(sc("#5AA9FF", .blue))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(sc("#1C1C1E", .black), in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}

// MARK: - Permission card (denied / limited) — G16-S07, G13-S10, calendar/location pre-prompts

public struct PermissionCard: View {
    private let icon: String
    private let title: String
    private let message: String
    private let actionTitle: String
    private let action: () -> Void

    public init(icon: String, title: String, message: String, actionTitle: String = "Open Settings", action: @escaping () -> Void) {
        self.icon = icon; self.title = title; self.message = message
        self.actionTitle = actionTitle; self.action = action
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(SCPalette.warning)
            Text(title).font(.headline).foregroundStyle(SCPalette.label)
            Text(message).font(.subheadline).foregroundStyle(SCPalette.secondary)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Text(actionTitle).font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(SCPalette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Pro feature gate — G16-S09, G03-S11 (shared-list/Pro gate)

public struct ProGateCard: View {
    private let feature: String
    private let message: String
    private let onUpgrade: () -> Void
    private let fallbackTitle: String?
    private let onFallback: (() -> Void)?

    public init(feature: String, message: String, onUpgrade: @escaping () -> Void,
                fallbackTitle: String? = nil, onFallback: (() -> Void)? = nil) {
        self.feature = feature; self.message = message; self.onUpgrade = onUpgrade
        self.fallbackTitle = fallbackTitle; self.onFallback = onFallback
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "crown.fill").font(.system(size: 32)).foregroundStyle(SCPalette.warning)
            Text(feature).font(.title3.weight(.semibold)).foregroundStyle(SCPalette.label)
            Text(message).font(.subheadline).foregroundStyle(SCPalette.secondary).multilineTextAlignment(.center)
            Button(action: onUpgrade) {
                Label("Upgrade to DoIT Pro", systemImage: "sparkles").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).tint(SCPalette.accent)
            if let fallbackTitle, let onFallback {
                Button(fallbackTitle, action: onFallback).font(.subheadline).foregroundStyle(SCPalette.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(SCPalette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Role-restricted notice — G16-S08

public struct RoleRestrictedNotice: View {
    private let role: String
    private let message: String

    public init(role: String, message: String) { self.role = role; self.message = message }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(SCPalette.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're a \(role)").font(.subheadline.weight(.semibold)).foregroundStyle(SCPalette.label)
                Text(message).font(.caption).foregroundStyle(SCPalette.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(SCPalette.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Conflict resolver — G16-S05/S06, G04-S15

public struct ConflictResolverCard: View {
    private let title: String
    private let mineLabel: String
    private let theirsLabel: String
    private let onKeepMine: () -> Void
    private let onUseTheirs: () -> Void

    public init(title: String = "Updated on another device",
                mineLabel: String, theirsLabel: String,
                onKeepMine: @escaping () -> Void, onUseTheirs: @escaping () -> Void) {
        self.title = title; self.mineLabel = mineLabel; self.theirsLabel = theirsLabel
        self.onKeepMine = onKeepMine; self.onUseTheirs = onUseTheirs
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold)).foregroundStyle(SCPalette.warning)
            row("This device", mineLabel)
            row("Newer (synced)", theirsLabel)
            HStack(spacing: 10) {
                Button("Keep mine", action: onKeepMine).buttonStyle(.bordered).frame(maxWidth: .infinity)
                Button("Use newer", action: onUseTheirs).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(SCPalette.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(SCPalette.secondary)
            Text(value).font(.subheadline).foregroundStyle(SCPalette.label)
        }
    }
}

// MARK: - Recoverable error — G16-S12

public struct RecoverableErrorView: View {
    private let title: String
    private let message: String
    private let retryTitle: String
    private let onRetry: () -> Void

    public init(title: String = "Something went wrong", message: String,
                retryTitle: String = "Try again", onRetry: @escaping () -> Void) {
        self.title = title; self.message = message; self.retryTitle = retryTitle; self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 34)).foregroundStyle(SCPalette.danger)
            Text(title).font(.headline).foregroundStyle(SCPalette.label)
            Text(message).font(.subheadline).foregroundStyle(SCPalette.secondary).multilineTextAlignment(.center)
            Button(action: onRetry) {
                Label(retryTitle, systemImage: "arrow.clockwise").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20).frame(maxWidth: .infinity)
        .background(SCPalette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Loading skeleton — G16-S10

public struct LoadingSkeleton: View {
    private let rows: Int
    public init(rows: Int = 5) { self.rows = rows }

    public var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6).frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).frame(height: 12)
                        RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 10)
                    }
                }
                .foregroundStyle(SCPalette.secondary.opacity(0.18))
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading")
    }
}

#if DEBUG
#Preview("State components") {
    ScrollView {
        VStack(spacing: 16) {
            StatusBanner(.offline, "Saved on this device. Changes will sync when you're back online.", actionTitle: "Retry") {}
            StatusBanner(.syncing, "Syncing your changes…")
            StatusBanner(.failed, "Couldn't reach the server.", actionTitle: "Retry") {}
            PermissionCard(icon: "bell.slash.fill", title: "Notifications are off",
                           message: "Turn on notifications to get reminders and routine alarms.") {}
            ProGateCard(feature: "Sharing is a Pro feature",
                        message: "Invite people to a shared list with role-based access.",
                        onUpgrade: {}, fallbackTitle: "Keep it personal", onFallback: {})
            RoleRestrictedNotice(role: "Viewer", message: "Only editors and the owner can change tasks in this list.")
            ConflictResolverCard(mineLabel: "Title: Buy groceries", theirsLabel: "Title: Buy groceries + milk",
                                 onKeepMine: {}, onUseTheirs: {})
            RecoverableErrorView(message: "We couldn't load your tasks. Check your connection and try again.") {}
            LoadingSkeleton(rows: 3)
            UndoToast("Task completed") {}
        }
        .padding()
    }
    .background(Color(hex: "#F2F2F7"))
}
#endif
