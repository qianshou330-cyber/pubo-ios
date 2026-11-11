import Foundation

/// Stable server ordering with a cursor independent of displayable user rows.
public struct FollowListPage: Sendable {
    public private(set) var rows: [Record] = []
    public private(set) var cursor: String?
    public private(set) var hasMore = true
    public init() {}
    public mutating func apply(_ response: JSONValue, reset: Bool, followers: Bool, limit: Int) throws {
        guard case .array(let values) = response else { throw APIError.invalidResponse }
        let raw = values.map(Record.init)
        guard raw.allSatisfy({ !$0.id.isEmpty }) else { throw APIError.invalidResponse }
        let previous = reset ? nil : cursor
        var next = reset ? [] : rows
        let userKey = followers ? "follower" : "followee"
        for row in raw where !Record(row[userKey]).id.isEmpty {
            if let index = next.firstIndex(where: { $0.id == row.id }) { next[index] = row }
            else { next.append(row) }
        }
        rows = next
        cursor = raw.last?.id
        hasMore = raw.count == limit && cursor != nil && cursor != previous
    }
}
