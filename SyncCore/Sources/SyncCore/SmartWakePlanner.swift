import Foundation

/// Smart wake suggestion (FR-ALRM-090): the time to wake so a morning routine of `routineMinutes`
/// (plus a `bufferMinutes` cushion) finishes before the day's first commitment. Pure + deterministic
/// so it's unit-tested; returns `nil` when there's no commitment to work back from.
public enum SmartWakePlanner {
    public static func suggestedWake(before firstCommitment: Date?, routineMinutes: Int,
                                     bufferMinutes: Int = 10, calendar: Calendar = .current) -> Date? {
        guard let commitment = firstCommitment else { return nil }
        let lead = max(0, routineMinutes) + max(0, bufferMinutes)
        return calendar.date(byAdding: .minute, value: -lead, to: commitment)
    }
}
