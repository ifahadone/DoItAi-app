import Foundation

/// The structured result of parsing a natural-language capture phrase (AppSpec §5.10, P1-H).
public struct ParsedQuickAdd: Equatable, Sendable {
    public var title: String
    public var dueAt: Date?
    public var tagNames: [String]
    public var priority: Priority
    /// Estimated duration in minutes, parsed from a trailing duration phrase ("1h", "90m", "1h30m",
    /// "for 45 min") — nil when none is present (FR-QADD-090).
    public var estimatedMinutes: Int?

    public init(title: String, dueAt: Date? = nil, tagNames: [String] = [], priority: Priority = .none,
                estimatedMinutes: Int? = nil) {
        self.title = title
        self.dueAt = dueAt
        self.tagNames = tagNames
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
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

        // Duration → estimatedMinutes, parsed AFTER date detection so a relative due phrase like
        // "in 2 hours" is consumed as a due date by NSDataDetector and only a leftover bare duration
        // ("1h", "30m", "for 45 min") is read as an estimate (FR-QADD-090).
        let estimatedMinutes = parseDuration(in: text)

        let title = (text as String)
            .replacingOccurrences(of: "\\bfor\\b\\s*$", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedQuickAdd(title: title, dueAt: dueAt, tagNames: tagNames, priority: priority,
                              estimatedMinutes: estimatedMinutes)
    }

    /// Find and strip the first duration phrase, returning total minutes. Prefers an hours(+minutes)
    /// form ("1h", "1 hr", "2 hours", "1h30m") and falls back to a minutes-only form ("30m", "45 min").
    private static func parseDuration(in text: NSMutableString) -> Int? {
        let ns = text as NSString
        let hourMin = "\\b(\\d{1,2})\\s*(?:h|hr|hrs|hour|hours)(?:\\s*(\\d{1,2})\\s*(?:m|min|mins|minute|minutes))?\\b"
        if let re = try? NSRegularExpression(pattern: hourMin, options: .caseInsensitive),
           let m = re.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) {
            let hours = Int(ns.substring(with: m.range(at: 1))) ?? 0
            var total = hours * 60
            if m.range(at: 2).location != NSNotFound { total += Int(ns.substring(with: m.range(at: 2))) ?? 0 }
            text.replaceCharacters(in: m.range, with: " ")
            return total > 0 ? total : nil
        }
        let minOnly = "\\b(\\d{1,3})\\s*(?:m|min|mins|minute|minutes)\\b"
        if let re = try? NSRegularExpression(pattern: minOnly, options: .caseInsensitive),
           let m = re.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) {
            let mins = Int((text as NSString).substring(with: m.range(at: 1))) ?? 0
            text.replaceCharacters(in: m.range, with: " ")
            return mins > 0 ? mins : nil
        }
        return nil
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
