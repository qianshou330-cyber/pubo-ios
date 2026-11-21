/// Accepted reply rows and paging eligibility for the shared note detail only.
public struct NoteDetailReplyPage: Sendable {
    public static let limit = 30
    public private(set) var rows: [Record] = []
    private var lastPageWasFull = false

    public init() {}

    public var olderCursor: String? {
        guard lastPageWasFull, let id = rows.last?.id, !id.isEmpty else { return nil }
        return id
    }

    public mutating func apply(_ response: JSONValue, older: Bool) throws {
        guard case .array(let items) = response else { throw APIError.invalidResponse }
        let result = Record.list(response)
        // Preserve mixed-page filtering and raw records, but do not turn a wholly
        // unrecognizable response into a confirmed empty page.
        guard items.isEmpty || !result.isEmpty else { throw APIError.invalidResponse }
        rows = older ? Records.merge(rows, result, limit: 10_000) : result
        lastPageWasFull = result.count == Self.limit
    }
}
