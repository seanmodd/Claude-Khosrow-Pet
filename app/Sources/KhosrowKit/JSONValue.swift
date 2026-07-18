import Foundation

/// A small, order-agnostic JSON value model used for merging Claude settings
/// without depending on `Any`/`NSDictionary`. Keeps merges pure and testable.
public indirect enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unsupported JSON value")
        }
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
}

public extension JSONValue {
    static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func parse(_ string: String) throws -> JSONValue {
        try parse(Data(string.utf8))
    }

    /// Pretty-printed, key-sorted serialization (stable output for diffs/tests).
    func serializedPretty() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(self)
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    subscript(_ key: String) -> JSONValue? {
        objectValue?[key]
    }
}

public extension JSONValue {
    /// Recursive deep merge. Objects merge key-by-key; for any non-object
    /// (arrays, scalars) the `overlay` wins. Used as the generic settings-merge
    /// primitive; hook arrays use the specialized append logic in
    /// ``ClaudeSettings`` instead.
    static func deepMerge(_ base: JSONValue, _ overlay: JSONValue) -> JSONValue {
        guard case .object(let b) = base, case .object(let o) = overlay else {
            return overlay
        }
        var result = b
        for (k, v) in o {
            if let existing = result[k] {
                result[k] = deepMerge(existing, v)
            } else {
                result[k] = v
            }
        }
        return .object(result)
    }
}
