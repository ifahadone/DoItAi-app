import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform semantic background/separator colors.
///
/// DoIT ships on iOS (AppSpec §5) where these map to UIKit's adaptive system colors (dark mode +
/// Increase Contrast for free). The AppKit equivalents are provided so `DesignSystem` also compiles
/// and previews on macOS during development (`swift build`), matching the SyncCore "build offline on
/// the Mac" approach. The two platforms pick the nearest native semantic color.
public extension Color {
    /// Primary surface behind content.
    static var doitBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.white
        #endif
    }

    /// Elevated/grouped surface (cards, rows).
    static var doitSurface: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color.gray.opacity(0.1)
        #endif
    }

    /// Hairline separator.
    static var doitSeparator: Color {
        #if canImport(UIKit)
        Color(uiColor: .separator)
        #elseif canImport(AppKit)
        Color(nsColor: .separatorColor)
        #else
        Color.gray.opacity(0.3)
        #endif
    }
}
