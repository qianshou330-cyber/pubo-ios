import Foundation

/// Mirrors the H5 channels page's account policy and explicit search scopes.
public enum ChannelSearchScope: String, CaseIterable, Identifiable, Sendable {
    case nameAndDescription, nameOnly
    public var id: String { rawValue }
    public var title: String { self == .nameOnly ? "仅名称" : "名称和说明" }
    public func request(query: String) -> [String: JSONValue] {
        ["query": .string(query.trimmingCharacters(in: .whitespacesAndNewlines)), "type": .string(rawValue)]
    }
}

public enum ChannelPolicy {
    /// Missing / malformed policy is not permission to create. Editing an
    /// existing channel is governed separately by ownership and the server.
    public static func canCreate(user: JSONValue) -> Bool {
        user["policies"]["canCreateChannel"] == .bool(true)
    }
    public static func canSave(kind: CollectionKind, creating: Bool, user: JSONValue) -> Bool {
        kind != .channel || !creating || canCreate(user: user)
    }
}
