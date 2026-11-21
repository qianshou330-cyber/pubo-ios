/// First-page status is independent of the rows retained during later requests.
public struct FavoritesReadPresentation: Equatable, Sendable {
    public let showsLoading: Bool
    public let showsError: Bool
    public let showsEmpty: Bool
    public let showsLoadMore: Bool

    public init(hasLoadedFirstPage: Bool, isLoading: Bool, hasError: Bool,
                hasRows: Bool, hasOlderCursor: Bool) {
        showsLoading = isLoading || (!hasLoadedFirstPage && !hasError)
        showsError = hasError && (hasLoadedFirstPage || !isLoading)
        showsEmpty = hasLoadedFirstPage && !hasRows && !isLoading && !hasError
        showsLoadMore = hasLoadedFirstPage && hasRows && hasOlderCursor && !isLoading
    }

    /// An unrecognizable reply is not a confirmed empty list.
    public static func pageRecords(_ response: JSONValue) throws -> [Record] {
        guard case .array(let items) = response else { throw APIError.invalidResponse }
        let rows = Record.list(response)
        guard items.isEmpty || !rows.isEmpty else { throw APIError.invalidResponse }
        return rows
    }
}
