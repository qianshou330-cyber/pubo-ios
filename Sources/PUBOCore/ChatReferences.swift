import Foundation

/// References carry their own revision: updating a parent message must not restore an old quote.
public enum ChatReferences {
    public static func ids(_ messages: [Record], draft: Record? = nil) -> Set<String> {
        var ids = Set(messages.compactMap { $0["replyToId"].string ?? $0["replyTo"]["id"].string })
        if let draft { ids.insert(draft.id) }
        ids.remove(""); return ids
    }

    public static func summary(_ target: Record) -> JSONValue {
        let alive = target["recalledAt"].isNull
        return .object([
            "id": .string(target.id), "fromUserId": target["fromUserId"],
            "text": alive && !target.text.isEmpty ? .string(String(String.UnicodeScalarView(target.text.unicodeScalars.prefix(200)))) : .null,
            "attachmentTypes": .strings(alive ? Array(Set(target["attachments"].array.compactMap { $0["kind"].string })).sorted() : []),
            "revision": target["revision"], "recalledAt": target["recalledAt"], "unavailable": .bool(false)
        ])
    }

    public static func unavailable(_ id: String) -> JSONValue {
        .object(["id": .string(id), "text": .null, "attachmentTypes": .array([]), "unavailable": .bool(true)])
    }

    public static func newest(_ old: JSONValue, _ incoming: JSONValue) -> JSONValue {
        if incoming.isNull { return old }
        if old.isNull || incoming["unavailable"].bool { return incoming }
        if old["unavailable"].bool || (!old["recalledAt"].isNull && incoming["recalledAt"].isNull) { return old }
        return incoming["revision"].int >= old["revision"].int ? incoming : old
    }

    public static func reconcile(_ messages: [Record], targets: [Record], missing: [String] = []) -> [Record] {
        let byID = Dictionary(targets.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a["revision"].int > b["revision"].int ? a : b })
        let missingIDs = Set(missing)
        return messages.map { message in
            guard let id = message["replyToId"].string ?? message["replyTo"]["id"].string else { return message }
            let update = missingIDs.contains(id) ? unavailable(id) : byID[id].map(summary) ?? .null
            var fields = message.raw.object
            fields["replyTo"] = newest(message["replyTo"], update)
            return Record(.object(fields))
        }
    }

    public static func label(_ value: JSONValue) -> String {
        if value["unavailable"].bool { return "原消息暂不可用" }
        if !value["recalledAt"].isNull { return "原消息已撤回" }
        let types = value["attachmentTypes"].array.compactMap(\.string).map { $0 == "voice" ? "语音" : $0 == "image" ? "图片" : "文件" }
        return ([value["text"].string ?? ""] + types).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct NotificationBadges: Equatable, Sendable {
    public private(set) var notification = false
    public private(set) var notificationCount: Int?
    public var chatCount = 0
    public var otherChat = false
    public init() {}
    public var notificationLabel: String? {
        guard notification else { return nil }
        guard let count = notificationCount, count > 0 else { return "•" }
        return count > 99 ? "99+" : String(count)
    }
    public mutating func applyAccount(_ account: JSONValue) {
        guard case .bool(let unread) = account["hasUnreadNotification"] else { return }
        notification = unread
        if unread, case .number(let count) = account["unreadNotificationsCount"], count > 0, count.rounded() == count {
            notificationCount = Int(min(count, 100))
        } else { notificationCount = nil }
    }
    public mutating func markNotificationsRead() { notification = false; notificationCount = nil }
    public var chatLabel: String? { chatCount > 0 ? (chatCount > 99 ? "99+" : String(chatCount)) : otherChat ? "•" : nil }
    public mutating func applyChat(_ summary: JSONValue) throws {
        guard case .number(let count) = summary["notificationUnreadCount"], count >= 0, count.rounded() == count,
              case .bool = summary["hasNotificationLegacyUnread"], case .bool = summary["hasUnreadRoom"] else { throw APIError.invalidResponse }
        chatCount = summary["notificationUnreadCount"].int
        otherChat = summary["hasNotificationLegacyUnread"].bool || summary["hasUnreadRoom"].bool
    }
}
