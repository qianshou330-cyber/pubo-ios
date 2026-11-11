import Foundation

/// Keep track of which query actually owns the displayed rows. An in-flight
/// response cannot acknowledge a reconnect that happened after it started.
public struct NotificationRefreshState: Sendable {
    public private(set) var loadedQuery: String?
    public private(set) var revision = 0
    private var loadedRevision = 0
    public init() {}
    public mutating func invalidate() { revision += 1 }
    public mutating func clearDisplayedQuery() { loadedQuery = nil; invalidate() }
    public mutating func didLoad(_ query: String, revision: Int) {
        loadedQuery = query
        loadedRevision = revision
    }
    public func shouldRefresh(_ query: String, atTop: Bool) -> Bool {
        atTop && loadedQuery == query && revision != loadedRevision
    }
}

public enum NotificationTab: String, CaseIterable, Sendable {
    case all, mentions, directNotes

    public var endpoint: String { self == .all ? "i/notifications-grouped" : "notes/mentions" }
    public var limit: Int { self == .all ? 20 : 10 }

    public func parameters(filter: NotificationKind?, until: String?, oldestFirst: Bool = false, date: Date? = nil) -> [String: JSONValue] {
        var result: [String: JSONValue] = ["limit": .number(Double(limit))]
        if self == .all, let filter { result["includeTypes"] = .strings([filter.rawValue]) }
        if self == .directNotes { result["visibility"] = .string("specified") }
        let forward = self != .all && oldestFirst
        if let until { result[forward ? "sinceId" : "untilId"] = .string(until) }
        else if self != .all, let date {
            result[forward ? "sinceDate" : "untilDate"] = .number(floor(date.timeIntervalSince1970 * 1000))
        } else if forward { result["sinceId"] = .string("0") }
        return result
    }

    /// The grouped endpoint folds a raw page before returning it. A short group
    /// page can have a full page of older notifications behind its last ID.
    public func canLoadOlder(_ page: [Record], previousCursor: String?) -> Bool {
        guard let cursor = page.last?.id, cursor != previousCursor else { return false }
        return self == .all || page.count == limit
    }
}

public enum NotificationKind: String, CaseIterable, Sendable {
    case note, follow, mention, reply, renote, quote, reaction, pollEnded
    case scheduledNotePosted, scheduledNotePostFailed, receiveFollowRequest, followRequestAccepted
    case app, roleAssigned, chatRoomInvitationReceived, achievementEarned, exportCompleted, test, login, createToken

    public init?(record: Record) {
        guard let raw = record["type"].string else { return nil }
        self.init(rawValue: raw.components(separatedBy: ":").first ?? raw)
    }

    public var title: String {
        switch self {
        case .note: "用户的新帖子"
        case .follow: "关注中"
        case .mention: "提及"
        case .reply: "回复"
        case .renote: "转贴"
        case .quote: "引用"
        case .reaction: "回应"
        case .pollEnded: "问卷调查结束"
        case .scheduledNotePosted: "定时发送成功"
        case .scheduledNotePostFailed: "定时发送失败"
        case .receiveFollowRequest: "收到关注请求"
        case .followRequestAccepted: "关注请求已通过"
        case .app: "关联应用的通知"
        case .roleAssigned: "授予的角色"
        case .chatRoomInvitationReceived: "您已被邀请加入群聊"
        case .achievementEarned: "取得的成就"
        case .exportCompleted: "已完成导出"
        case .test: "测试通知"
        case .login: "登录"
        case .createToken: "创建访问令牌"
        }
    }
}
