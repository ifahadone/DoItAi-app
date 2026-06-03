import Foundation

/// A type-erased, `Codable` JSON value.
///
/// The sync push contract (ApiSpec §6.1) sends a sparse **patch** of changed fields:
/// `"fields": { "title": "…", "status": 1, "scheduledStart": "…Z", "tagIds": ["…"] }`.
/// Field values are heterogeneous (string, int, double, bool, null, array, object), so the field
/// bag is modeled as `[String: AnyCodable]`. This wrapper encodes/decodes any JSON scalar or
/// container while preserving the distinction between integers and doubles where possible (so
/// `status: 1` does not serialize as `1.0`).
///
/// `Sendable` because every stored case is a value type; this lets ``OutboxOp`` and the DTOs cross
/// actor boundaries safely.
public enum AnyCodable: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([AnyCodable])
    case object([String: AnyCodable])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        // Order matters: try Bool before Int/Double (JSON `true`/`false` would otherwise be
        // ambiguous on some platforms), and Int before Double so whole numbers stay integers.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyCodable].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyCodable].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable: unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Ergonomic construction

public extension AnyCodable {
    /// Best-effort wrapping of a Swift value into an ``AnyCodable``.
    ///
    /// Supports the JSON-representable scalars and (recursively) `Array`/`Dictionary` of the same.
    /// Returns `nil` for unsupported types so callers can decide how to handle them rather than
    /// crashing. `Date` is intentionally **not** auto-converted here — encode dates as ISO-8601
    /// strings at the call site (see ``ISO8601`` / the DTO encoder) so the wire format is explicit.
    static func wrap(_ value: Any?) -> AnyCodable? {
        switch value {
        case nil, is NSNull:
            return AnyCodable.null
        case let v as Bool:
            return .bool(v)
        case let v as Int:
            return .int(v)
        case let v as Double:
            return .double(v)
        case let v as String:
            return .string(v)
        case let v as [Any?]:
            return .array(v.map { AnyCodable.wrap($0) ?? .null })
        case let v as [String: Any?]:
            var out: [String: AnyCodable] = [:]
            for (key, element) in v { out[key] = AnyCodable.wrap(element) ?? .null }
            return .object(out)
        default:
            return nil
        }
    }
}
