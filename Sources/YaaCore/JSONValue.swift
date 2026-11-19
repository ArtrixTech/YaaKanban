import Foundation

/// Untyped JSON, used for hook payloads whose shape varies per agent.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var string: String? {
        switch self {
        case .string(let s): return s
        // Int(n) traps outside its range; 2^53 keeps integral output exact.
        case .number(let n): return n == n.rounded() && abs(n) < 9.0e15 ? String(Int(n)) : String(n)
        case .bool(let b): return String(b)
        default: return nil
        }
    }

    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var number: Double? { if case .number(let n) = self { return n }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    /// Compact JSON text, or the bare string for `.string`.
    public var text: String {
        if case .string(let s) = self { return s }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? String(data: enc.encode(self), encoding: .utf8)) ?? ""
    }

    public static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// The first complete top-level object or array in `data`, ignoring what follows it. Claude
    /// Code rewrites its session file in place, and a shorter record leaves the old one's tail.
    public static func parseLeading(_ data: Data) -> JSONValue? {
        if let v = parse(data) { return v }
        var depth = 0, inString = false, escaped = false
        for (i, b) in data.enumerated() {
            if inString {
                if escaped { escaped = false } else if b == UInt8(ascii: "\\") { escaped = true } else if b == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch b {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                if depth == 0 { return parse(data.prefix(i + 1)) }
                if depth < 0 { return nil }
            default: break
            }
        }
        return nil
    }
}
