import SwiftUI

public extension Color {
    /// Initialize from a hex string — `"#RRGGBB"`, `"#RRGGBBAA"`, or `"#RGB"` (the leading `#` is
    /// optional). Returns `nil` for an unparsable/absent value so callers can fall back to a theme
    /// token. List/tag rows store their color as a hex string on the wire (ApiSpec §5).
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt64(s, radix: 16) else { return nil }

        let r, g, b, a: Double
        switch s.count {
        case 3: // RGB (4 bits/channel)
            r = Double((value & 0xF00) >> 8) / 15
            g = Double((value & 0x0F0) >> 4) / 15
            b = Double(value & 0x00F) / 15
            a = 1
        case 6: // RRGGBB
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        case 8: // RRGGBBAA
            r = Double((value & 0xFF000000) >> 24) / 255
            g = Double((value & 0x00FF0000) >> 16) / 255
            b = Double((value & 0x0000FF00) >> 8) / 255
            a = Double(value & 0x000000FF) / 255
        default:
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
