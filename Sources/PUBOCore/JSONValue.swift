import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue { object[key] ?? .null }
    public var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    public var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var bool: Bool { if case .bool(let v) = self { return v }; return false }
    public var int: Int { if case .number(let v) = self, v.isFinite, v < Double(Int.max), v > Double(Int.min) { return Int(v) }; return 0 }
    public var isNull: Bool { self == .null }
    public static func strings(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }
}

/// Preserve unknown server fields while only interpreting the current contract.
public struct Record: Codable, Equatable, Identifiable, Sendable {
    public var raw: JSONValue
    public init(_ raw: JSONValue) { self.raw = raw }
    public var id: String { raw["id"].string ?? "" }
    public subscript(_ key: String) -> JSONValue { raw[key] }
    public var displayName: String { raw["name"].string.flatMap { $0.isEmpty ? nil : $0 } ?? raw["username"].string ?? "用户" }
    public var user: Record { Record(raw["user"]) }
    public var text: String { raw["text"].string ?? "" }
    public static func list(_ value: JSONValue) -> [Record] { value.array.map(Record.init).filter { !$0.id.isEmpty } }
}

public enum Records {
    public static func merge(_ existing: [Record], _ incoming: [Record], newestFirst: Bool = true, limit: Int = 200) -> [Record] {
        var map = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for item in incoming where !item.id.isEmpty { map[item.id] = item }
        let sorted = map.values.sorted { newestFirst ? $0.id > $1.id : $0.id < $1.id }
        return newestFirst ? Array(sorted.prefix(limit)) : Array(sorted.suffix(limit))
    }
}
