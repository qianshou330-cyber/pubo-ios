import Foundation

/// Member offsets track requested IDs, not the number of available user records.
public struct ContactMemberPage: Sendable {
    public private(set) var ids: [String] = []
    public private(set) var rows: [Record] = []
    public private(set) var offset = 0
    public var hasMore: Bool { offset < ids.count }
    public init() {}
    public init(ids: [String]) {
        var seen = Set<String>()
        self.ids = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    public var nextIDs: [String] { Array(ids.dropFirst(offset).prefix(50)) }
    @discardableResult public mutating func apply(_ response: JSONValue, requested: [String]) throws -> Bool {
        guard requested == nextIDs, !requested.isEmpty, case .array(let values) = response else { throw APIError.invalidResponse }
        let users = values.map(Record.init)
        guard users.allSatisfy({ !$0.id.isEmpty && requested.contains($0.id) }), Set(users.map(\.id)).count == users.count else { throw APIError.invalidResponse }
        let indexed = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        rows += requested.compactMap { indexed[$0] }
        offset += requested.count
        return users.count == requested.count
    }
}
