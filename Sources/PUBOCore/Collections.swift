import Foundation

public enum CollectionKind: String, CaseIterable, Identifiable, Sendable {
    case channel, list, antenna, clip, gallery
    public var id: String { rawValue }
    public var title: String { switch self { case .channel: "频道"; case .list: "列表"; case .antenna: "天线"; case .clip: "剪藏"; case .gallery: "图库" } }
    public var base: String { switch self { case .channel: "channels"; case .list: "users/lists"; case .antenna: "antennas"; case .clip: "clips"; case .gallery: "gallery/posts" } }
    public var idKey: String { switch self { case .channel: "channelId"; case .list: "listId"; case .antenna: "antennaId"; case .clip: "clipId"; case .gallery: "postId" } }
    public var nameKey: String { self == .gallery ? "title" : "name" }
    public var feed: String { switch self { case .channel: "channels/timeline"; case .list: "notes/user-list-timeline"; case .antenna: "antennas/notes"; case .clip: "clips/notes"; case .gallery: "" } }
}

public enum CollectionFields {
    public static func keywords(_ text: String) -> JSONValue {
        .array(text.split(whereSeparator: \.isNewline).map { .strings($0.split(whereSeparator: \.isWhitespace).map(String.init)) }.filter { !$0.array.isEmpty })
    }
    public static func keywordText(_ value: JSONValue) -> String { value.array.map { $0.array.compactMap(\.string).joined(separator: " ") }.joined(separator: "\n") }
    /// Updates preserve unknown server fields, and never re-send unchanged values.
    public static func changes(_ fields: [String: JSONValue], from baseline: [String: JSONValue]) -> [String: JSONValue] { fields.filter { baseline[$0.key] != $0.value } }
    /// Legacy endpoints reset these fields when omitted. Preserve the freshly read value.
    public static func update(_ changes: [String: JSONValue], kind: CollectionKind, latest: JSONValue) -> [String: JSONValue] {
        var result = changes
        if kind == .clip, result["description"] == nil { result["description"] = latest["description"] }
        if kind == .clip, result["description"]?.string == "" { result["description"] = .null }
        if kind == .gallery, result["isSensitive"] == nil { result["isSensitive"] = .bool(latest["isSensitive"].bool) }
        return result
    }
}
