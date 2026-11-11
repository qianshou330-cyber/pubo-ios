import Foundation

public enum FollowRequestDirection: String, CaseIterable, Identifiable, Sendable {
    case received, sent
    public var id: String { rawValue }
    public var title: String { self == .received ? "收到的申请" : "已发送的申请" }
    public var endpoint: String { self == .received ? "following/requests/list" : "following/requests/sent" }
    public var userKey: String { self == .received ? "follower" : "followee" }
    public static func initial(user: JSONValue) -> Self { user["isLocked"].bool ? .received : .sent }
}

public enum FollowRequestDecision: String, Sendable {
    case accept, reject, cancel
    public var endpoint: String { "following/requests/" + rawValue }
    public var title: String { self == .accept ? "接受" : self == .reject ? "拒绝" : "撤回申请" }
    public var requiresConfirmation: Bool { self != .accept }
    public func allowed(in direction: FollowRequestDirection) -> Bool {
        direction == .sent ? self == .cancel : self != .cancel
    }
}

/// Cursor belongs to the server page, not the remaining rendered rows. Removing
/// every request on a page must not lose access to the next page.
public struct FollowRequestPage: Sendable {
    public private(set) var rows: [Record] = []
    public private(set) var cursor: String?
    public private(set) var hasMore = true
    private var handledIDs = Set<String>()
    public init() {}
    public mutating func apply(_ response: [Record], reset: Bool, limit: Int) {
        let previous = reset ? nil : cursor
        if reset { rows = [] }
        for row in response where !row.id.isEmpty && !handledIDs.contains(row.id) {
            if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index] = row }
            else { rows.append(row) }
        }
        cursor = response.last?.id
        hasMore = response.count == limit && cursor != nil && cursor != previous
    }
    public mutating func handled(_ requestID: String) {
        handledIDs.insert(requestID)
        rows.removeAll { $0.id == requestID }
    }
}
