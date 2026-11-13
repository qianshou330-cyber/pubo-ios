import Foundation

/// A direct peer and a room may have the same server ID; their routes never do.
public struct ChatConversation: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case user, room }
    public let kind: Kind
    public let target: Record
    public var raw: JSONValue
    public var id: String { kind.rawValue + ":" + target.id }
    public var message: Record { Record(raw["lastMessage"]) }
    public var pinnedAt: String? { kind == .user ? raw["pinnedAt"].string : nil }
    public var muted: Bool { kind == .user && raw["isMuted"].bool }
    public var unreadCount: Int { max(0, raw["unreadCount"].int) }
    public var legacyUnread: Bool { raw["hasLegacyUnread"].bool }
    public var badge: String? { unreadCount > 0 ? (unreadCount > 99 ? "99+" : String(unreadCount)) : nil }
    public static func direct(_ value: JSONValue) -> ChatConversation? {
        let user = Record(value["user"])
        guard !user.id.isEmpty else { return nil }
        return .init(kind: .user, target: user, raw: value)
    }
    public static func room(_ value: JSONValue, viewer: String) -> ChatConversation? {
        var room = value["toRoom"].object
        guard let id = value["toRoomId"].string ?? room["id"]?.string, !id.isEmpty else { return nil }
        room["id"] = .string(id)
        return .init(kind: .room, target: Record(.object(room)), raw: .object([
            "lastMessage": value, "hasLegacyUnread": .bool(!value["isRead"].bool && value["fromUserId"].string != viewer),
        ]))
    }
    /// Nil snapshots retain their successful previous source. Refreshing never drops loaded direct pages.
    public static func merge(_ previous: [Self], ordinary: [Self]?, pins: [Self]?, rooms: [Self]?) -> [Self] {
        var map = Dictionary(previous.filter { $0.kind == .user || rooms == nil }.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        if pins != nil {
            for (id, var row) in map where row.kind == .user && row.pinnedAt != nil {
                var fields = row.raw.object; fields["pinnedAt"] = .null; row.raw = .object(fields); map[id] = row
            }
        }
        for row in (ordinary ?? []) + (rooms ?? []) + (pins ?? []) { map[row.id] = row }
        return map.values.sorted {
            if let a = $0.pinnedAt, let b = $1.pinnedAt { return a == b ? $0.id < $1.id : a > b }
            if $0.pinnedAt != nil || $1.pinnedAt != nil { return $0.pinnedAt != nil }
            let a = $0.message["createdAt"].string ?? "", b = $1.message["createdAt"].string ?? ""
            if a != b { return a > b }
            if $0.message.id != $1.message.id { return $0.message.id > $1.message.id }
            return $0.id < $1.id
        }
    }
}

public struct ChatReaction: Identifiable, Equatable, Sendable {
    public let emoji: String
    public let user: Record
    public var id: String { user.id + ":" + SocialContent.chatReactionKey(emoji) }
    public static func rows(_ values: [JSONValue]) -> [Self] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let emoji = value["reaction"].string, !emoji.isEmpty else { return nil }
            var user = value["user"].object
            if user["id"]?.string == nil { user["id"] = value["userId"] }
            let row = Self(emoji: emoji, user: Record(.object(user)))
            guard !row.user.id.isEmpty, seen.insert(row.id).inserted else { return nil }
            return row
        }
    }
    /// Clicking another person's duplicate emoji must not remove the viewer's reaction.
    public func isActionable(viewer: String, all: [Self]) -> Bool {
        user.id == viewer || !all.contains { $0.user.id == viewer && SocialContent.chatReactionKey($0.emoji) == SocialContent.chatReactionKey(emoji) }
    }
    public func desiredPresence(viewer: String) -> Bool { user.id != viewer }
}

public struct ChatStreamEvent: Sendable {
    public let room: Bool
    public let targetID: String
    public let kind: String
    public let body: JSONValue
    public init(room: Bool, targetID: String, kind: String, body: JSONValue) {
        self.room = room; self.targetID = targetID; self.kind = kind; self.body = body
    }
    public var messageID: String? { body["messageId"].string ?? body["id"].string ?? body.string }
}

public enum ChatDays {
    public static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
    public struct Pair: Equatable, Sendable {
        public let older: String
        public let newer: String
        public var privateText: String { newer + " · " + older }
        public var chronologicalText: String { older + " · " + newer }
    }
    /// Input remains chronological; this only describes a boundary, never reorders rows.
    public static func pair(previous: Record?, current: Record, calendar: Calendar = .current) -> Pair? {
        guard let previous, let before = date(previous["createdAt"].string), let after = date(current["createdAt"].string), !calendar.isDate(before, inSameDayAs: after) else { return nil }
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        // Deliberate native enhancement: retain years at a cross-year boundary.
        f.dateFormat = calendar.component(.year, from: before) == calendar.component(.year, from: after) ? "M/d" : "yyyy/M/d"
        return Pair(older: f.string(from: before), newer: f.string(from: after))
    }
    public static func separator(previous: Record?, current: Record, calendar: Calendar = .current) -> String? {
        pair(previous: previous, current: current, calendar: calendar)?.chronologicalText
    }
}
