import Foundation

/// The structured result of parsing a natural-language capture phrase (AppSpec §5.10, P1-H).
public struct ParsedQuickAdd: Equatable, Sendable {
    public var title: String
    public var dueAt: Date?
    public var tagNames: [String]
    public var priority: Priority

    public init(title: String, dueAt: Date? = nil, tagNames: [String] = [], priority: Priority = .none) {
        self.title = title
        self.dueAt = dueAt
        self.tagNames = tagNames
        self.priority = priority
    }
}

/// On-device natural-language quick-add (DevelopmentPlan P1-H). Turns a phrase like
/// `"Lunch with Sam tomorrow 1pm #work !p1"` into structured task fields the UI previews before save.
/// Pure Foundation (`NSDataDetector` for dates + token regexes) so it lives in `SyncCore` and is
/// unit-tested — the cloud-AI parse is a separate Phase-4 surface.
///
/// Tokens: `#tag` → tags · `!p1`…`!p4` (or `!1`…`!4`) → priority (`!1` = most urgent) · any date/time
/// phrase `NSDataDetector` recognizes → due date. Everything left is the title.
public enum QuickAddParser {
    public static func parse(_ input: String) -> ParsedQuickAdd {
        let text = NSMutableString(string: input)

        // #tags (preserve input order)
        var tagNames: [String] = []
        removeMatches("#(\\w+)", in: text) { tagNames.insert($0.lowercased(), at: 0) }

        // !priority — !p1…!p4 or !1…!4 (1 = most urgent)
        var priority: Priority = .none
        removeMatches("!p?([1-4])\\b", in: text, options: .caseInsensitive) { capture in
            if let n = Int(capture), let p = Priority(rawValue: 5 - n) { priority = p }
        }

        // First date/time phrase via NSDataDetector (run after stripping tokens to avoid false hits).
        var dueAt: Date?
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let s = text as String
            let range = NSRange(location: 0, length: (s as NSString).length)
            if let match = detector.firstMatch(in: s, options: [], range: range), let date = match.date {
                dueAt = date
                text.replaceCharacters(in: match.range, with: " ")
            }
        }

        let title = (text as String)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedQuickAdd(title: title, dueAt: dueAt, tagNames: tagNames, priority: priority)
    }

    /// Remove every match of `pattern` from `text` (back-to-front so ranges stay valid), passing each
    /// first capture group to `capture`.
    private static func removeMatches(
        _ pattern: String,
        in text: NSMutableString,
        options: NSRegularExpression.Options = [],
        capture: ((String) -> Void)? = nil
    ) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let matches = re.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            if let capture, match.numberOfRanges > 1 {
                capture(text.substring(with: match.range(at: 1)))
            }
            text.replaceCharacters(in: match.range, with: " ")
        }
    }
}
