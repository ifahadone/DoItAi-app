import Foundation

/// Centralized JSON encoder/decoder configured for the DoIT wire contract.
///
/// The API uses **RFC 3339 UTC** timestamps (ApiSpec §3), e.g. `2026-06-03T08:30:00Z`, optionally
/// with fractional seconds. `JSONCoding` provides a decoder that accepts both forms and an encoder
/// that always emits UTC. Field names are camelCase, matching the DTOs, so no key strategy is set.
///
/// Use these instead of bare `JSONEncoder()` / `JSONDecoder()` so date handling stays consistent
/// everywhere (DTO round-trips, APIClient bodies, pull-payload decoding).
///
/// `ISO8601DateFormatter` is not `Sendable`, so formatters are created **per factory call** and
/// captured by the strategy closure rather than shared via a global `static let` (which would be a
/// data race under Swift 6 strict concurrency). A formatter is built once per encoder/decoder, not
/// per value, so the cost is negligible.
public enum JSONCoding {
    /// An encoder that serializes `Date` as RFC 3339 UTC **with fractional seconds**. Sub-second
    /// precision matters: `clientUpdatedAt` drives the server's field-level LWW, so two edits to the
    /// same field within one second must get strictly-ordered timestamps or the later edit ties and is
    /// dropped. The server emits + parses fractional RFC 3339, and the decoder above tolerates both.
    public static func makeEncoder() -> JSONEncoder {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    /// A decoder that parses RFC 3339 UTC, tolerating both fractional and non-fractional seconds.
    public static func makeDecoder() -> JSONDecoder {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = withFractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected RFC 3339 date string, got \(raw)"
            )
        }
        return decoder
    }
}
