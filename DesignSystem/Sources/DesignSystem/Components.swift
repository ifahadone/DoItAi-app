import SwiftUI

// DoIT's first real component library (AppSpec §11, DevelopmentPlan P1-K). These are dependency-free
// SwiftUI views that take PRIMITIVES (not app models or SyncCore types) so `DesignSystem` stays pure
// and previewable on its own. Feature screens map their models onto these. All consume the active
// ``Theme`` from the environment — no hardcoded colors or spacing.

// MARK: - PriorityChip

/// A compact priority flag. `level` is the wire value (0 none, 1 p4 … 4 p1). Renders nothing for 0.
public struct PriorityChip: View {
    @Environment(\.theme) private var theme
    private let level: Int

    public init(level: Int) { self.level = level }

    public var body: some View {
        if (1...4).contains(level) {
            Label(label, systemImage: "flag.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .accessibilityLabel("Priority \(label)")
        }
    }

    /// Wire level 4 is the most urgent ("P1"); level 1 is least ("P4").
    private var label: String { "P\(5 - level)" }
    private var color: Color {
        switch level {
        case 4: return theme.colors.statusOverdue // p1 — red
        case 3: return .orange                    // p2
        case 2: return .yellow                    // p3
        default: return theme.colors.statusPlanned // p4 — blue
        }
    }
}

// MARK: - TagPill

/// A small tag capsule: a color dot + name. `colorHex` falls back to the accent tint when nil/invalid.
public struct TagPill: View {
    @Environment(\.theme) private var theme
    private let name: String
    private let colorHex: String?

    public init(name: String, colorHex: String? = nil) {
        self.name = name
        self.colorHex = colorHex
    }

    public var body: some View {
        let tint = Color(hex: colorHex) ?? theme.colors.accent
        HStack(spacing: theme.spacing.xs) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(name).font(.caption2)
        }
        .padding(.horizontal, theme.spacing.sm)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag \(name)")
    }
}

// MARK: - ListChip (inline) + ListHeader (section)

/// An inline list badge used on a task row (name + SF Symbol, tinted by the list color).
public struct ListChip: View {
    @Environment(\.theme) private var theme
    private let name: String
    private let systemImage: String
    private let colorHex: String?

    public init(name: String, systemImage: String = "list.bullet", colorHex: String? = nil) {
        self.name = name
        self.systemImage = systemImage
        self.colorHex = colorHex
    }

    public var body: some View {
        let tint = Color(hex: colorHex) ?? theme.colors.accent
        Label(name, systemImage: systemImage)
            .font(.caption2)
            .padding(.horizontal, theme.spacing.sm)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .accessibilityLabel("List \(name)")
    }
}

/// A section header for a list/group (icon + name + optional count).
public struct ListHeader: View {
    @Environment(\.theme) private var theme
    private let name: String
    private let systemImage: String
    private let colorHex: String?
    private let count: Int?
    private let isShared: Bool
    private let isJoined: Bool

    public init(name: String, systemImage: String = "list.bullet", colorHex: String? = nil,
                count: Int? = nil, isShared: Bool = false, isJoined: Bool = false) {
        self.name = name
        self.systemImage = systemImage
        self.colorHex = colorHex
        self.count = count
        self.isShared = isShared
        self.isJoined = isJoined
    }

    public var body: some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: systemImage).foregroundStyle(Color(hex: colorHex) ?? theme.colors.accent)
            Text(name).font(.headline)
            if isShared {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(isJoined ? "Shared with you" : "Shared list")
            }
            Spacer(minLength: 0)
            if let count {
                Text("\(count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - EmptyStateView

/// A centered empty-state placeholder (icon + title + message). Cross-platform — does NOT use
/// `ContentUnavailableView` (macOS 14+) so the package still builds on macOS 13 for `swift build`.
public struct EmptyStateView: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let systemImage: String
    private let message: String?

    public init(title: String, systemImage: String, message: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }

    public var body: some View {
        VStack(spacing: theme.spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(theme.colors.accent.opacity(0.7))
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(theme.spacing.xl)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - TaskRow

/// The canonical task row: a completion toggle, title (strikethrough when done), and a metadata line
/// (priority · list · tags · due · pending-sync). Takes display primitives + an optional `onToggle`;
/// the feature layer maps its `TaskModel` onto this.
public struct TaskRow: View {
    @Environment(\.theme) private var theme

    /// The task's list, pre-resolved by the caller (DesignSystem has no model layer).
    public struct ListBadge: Equatable, Sendable {
        public var name: String
        public var systemImage: String
        public var colorHex: String?
        public init(name: String, systemImage: String = "list.bullet", colorHex: String? = nil) {
            self.name = name
            self.systemImage = systemImage
            self.colorHex = colorHex
        }
    }

    private let title: String
    private let isDone: Bool
    private let priorityLevel: Int
    private let list: ListBadge?
    private let tags: [String]
    private let dueText: String?
    private let isPendingSync: Bool
    private let onToggle: (() -> Void)?

    public init(
        title: String,
        isDone: Bool = false,
        priorityLevel: Int = 0,
        list: ListBadge? = nil,
        tags: [String] = [],
        dueText: String? = nil,
        isPendingSync: Bool = false,
        onToggle: (() -> Void)? = nil
    ) {
        self.title = title
        self.isDone = isDone
        self.priorityLevel = priorityLevel
        self.list = list
        self.tags = tags
        self.dueText = dueText
        self.isPendingSync = isPendingSync
        self.onToggle = onToggle
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.md) {
            toggle
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(title)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? Color.secondary : Color.primary)
                if hasMeta {
                    HStack(spacing: theme.spacing.sm) {
                        PriorityChip(level: priorityLevel)
                        if let list {
                            ListChip(name: list.name, systemImage: list.systemImage, colorHex: list.colorHex)
                        }
                        ForEach(tags, id: \.self) { TagPill(name: $0) }
                        if let dueText {
                            Label(dueText, systemImage: "calendar").font(.caption2).foregroundStyle(.secondary)
                        }
                        if isPendingSync {
                            Text("Pending sync").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var hasMeta: Bool {
        (1...4).contains(priorityLevel) || list != nil || !tags.isEmpty || dueText != nil || isPendingSync
    }

    @ViewBuilder private var toggle: some View {
        let image = isDone ? "checkmark.circle.fill" : "circle"
        let tint = isDone ? theme.colors.statusDone : theme.colors.accent
        if let onToggle {
            Button(action: onToggle) {
                Image(systemName: image).foregroundStyle(tint).font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Mark not done" : "Mark done")
        } else {
            Image(systemName: image).foregroundStyle(tint).font(.title3)
        }
    }
}
