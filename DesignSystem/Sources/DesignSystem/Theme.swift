import SwiftUI

/// DoIT's semantic design tokens (AppSpec §11).
///
/// The look is "clean, calm, content-first; color comes from lists/tags and the sectograph, not
/// chrome." Tokens are defined once here and consumed via the SwiftUI `Environment` (see
/// ``EnvironmentValues/theme``) so views never hardcode raw colors or magic spacing numbers. Colors
/// resolve to system semantic colors where possible so Light/Dark/auto and Increase Contrast work
/// for free; brand-specific tokens can later be backed by an asset catalog in the app target.
///
/// This is intentionally minimal for Phase 0. Typography ramps, elevation, and the component library
/// (TaskRow, PriorityChip, TagPill, …) arrive in Phase 1+ (AppSpec §11, DevelopmentPlan Phase 1).
public struct Theme: Sendable {
    public var colors: ColorTokens
    public var spacing: SpacingScale
    public var radii: CornerRadii

    public init(
        colors: ColorTokens = ColorTokens(),
        spacing: SpacingScale = SpacingScale(),
        radii: CornerRadii = CornerRadii()
    ) {
        self.colors = colors
        self.spacing = spacing
        self.radii = radii
    }

    /// The default DoIT theme.
    public static let `default` = Theme()
}

/// Semantic color tokens (AppSpec §11). Backed by system semantic colors so dark mode + contrast
/// adapt automatically. `accent` is the app tint; `status*` convey task state — but per the
/// accessibility rule (AppSpec §12) status must never be color-*only*, so these pair with icons/labels.
public struct ColorTokens: Sendable {
    public var background: Color
    public var surface: Color
    public var separator: Color
    public var accent: Color
    public var statusPlanned: Color
    public var statusDone: Color
    public var statusOverdue: Color

    public init(
        background: Color = .doitBackground,
        surface: Color = .doitSurface,
        separator: Color = .doitSeparator,
        accent: Color = .accentColor,
        statusPlanned: Color = .blue,
        statusDone: Color = .green,
        statusOverdue: Color = .red
    ) {
        self.background = background
        self.surface = surface
        self.separator = separator
        self.accent = accent
        self.statusPlanned = statusPlanned
        self.statusDone = statusDone
        self.statusOverdue = statusOverdue
    }
}

/// A 4-pt spacing grid (AppSpec §11). Use these named steps instead of literal padding values.
public struct SpacingScale: Sendable {
    /// 4 pt.
    public let xs: CGFloat
    /// 8 pt.
    public let sm: CGFloat
    /// 12 pt.
    public let md: CGFloat
    /// 16 pt.
    public let lg: CGFloat
    /// 24 pt.
    public let xl: CGFloat
    /// 32 pt.
    public let xxl: CGFloat

    public init(
        xs: CGFloat = 4,
        sm: CGFloat = 8,
        md: CGFloat = 12,
        lg: CGFloat = 16,
        xl: CGFloat = 24,
        xxl: CGFloat = 32
    ) {
        self.xs = xs
        self.sm = sm
        self.md = md
        self.lg = lg
        self.xl = xl
        self.xxl = xxl
    }
}

/// Corner radius tokens (AppSpec §11).
public struct CornerRadii: Sendable {
    public let small: CGFloat
    public let medium: CGFloat
    public let large: CGFloat

    public init(small: CGFloat = 8, medium: CGFloat = 12, large: CGFloat = 20) {
        self.small = small
        self.medium = medium
        self.large = large
    }
}
