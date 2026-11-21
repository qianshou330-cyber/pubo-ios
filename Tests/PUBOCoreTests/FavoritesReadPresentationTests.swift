import XCTest
@testable import PUBOCore

final class FavoritesReadPresentationTests: XCTestCase {
    private func state(loaded: Bool = false, busy: Bool = false, error: Bool = false,
                       rows: Bool = false, cursor: Bool = false) -> FavoritesReadPresentation {
        FavoritesReadPresentation(hasLoadedFirstPage: loaded, isLoading: busy,
                                 hasError: error, hasRows: rows, hasOlderCursor: cursor)
    }

    func testUnrequestedAndPendingFirstPageOnlyShowLoading() {
        for pending in [false, true] {
            let value = state(busy: pending, cursor: true)
            XCTAssertTrue(value.showsLoading)
            XCTAssertFalse(value.showsError)
            XCTAssertFalse(value.showsEmpty)
            XCTAssertFalse(value.showsLoadMore)
        }
    }

    func testFirstErrorHasNoEmptyOrOlderActionAndRetryShowsLoading() {
        let failed = state(error: true, cursor: true)
        XCTAssertTrue(failed.showsError)
        XCTAssertFalse(failed.showsLoading)
        XCTAssertFalse(failed.showsEmpty)
        XCTAssertFalse(failed.showsLoadMore)
        XCTAssertEqual(state(busy: true, error: true, cursor: true), state(busy: true))
    }

    func testConfirmedEmptyIsNotReusedForARefreshFailure() {
        let empty = state(loaded: true, cursor: true)
        XCTAssertTrue(empty.showsEmpty)
        XCTAssertFalse(empty.showsLoading)
        XCTAssertFalse(empty.showsError)
        XCTAssertFalse(empty.showsLoadMore)
        let refreshing = state(loaded: true, busy: true)
        XCTAssertTrue(refreshing.showsLoading)
        XCTAssertFalse(refreshing.showsEmpty)
        let failedRefresh = state(loaded: true, error: true)
        XCTAssertTrue(failedRefresh.showsError)
        XCTAssertFalse(failedRefresh.showsEmpty)
        XCTAssertFalse(failedRefresh.showsLoadMore)
    }

    func testLoadedRowsOnlyOfferOlderReadingWithAKnownCursor() {
        XCTAssertFalse(state(loaded: true, rows: true).showsLoadMore)
        XCTAssertTrue(state(loaded: true, rows: true, cursor: true).showsLoadMore)
        let paging = state(loaded: true, busy: true, rows: true, cursor: true)
        XCTAssertTrue(paging.showsLoading)
        XCTAssertFalse(paging.showsLoadMore)
        XCTAssertFalse(paging.showsEmpty)
        let failedTail = state(loaded: true, error: true, rows: true, cursor: true)
        XCTAssertTrue(failedTail.showsError)
        XCTAssertTrue(failedTail.showsLoadMore)
        XCTAssertFalse(failedTail.showsEmpty)
    }

    func testEmptyArrayIsValidButWrongShapeAndUnidentifiableRowsAreNot() throws {
        XCTAssertEqual(try FavoritesReadPresentation.pageRecords(.array([])), [])
        for invalid in [JSONValue.null, .object([:]), .array([.object(["note": .null])])] {
            XCTAssertThrowsError(try FavoritesReadPresentation.pageRecords(invalid))
        }
    }

    func testKnownFavoriteWrapperIDsKeepOrderAndPreserveNullNotePayload() throws {
        let first = JSONValue.object(["id": .string("favorite3"), "note": .null])
        let second = JSONValue.object(["id": .string("favorite1"), "note": .object(["id": .string("note9")])])
        let rows = try FavoritesReadPresentation.pageRecords(.array([first, second]))
        XCTAssertEqual(rows.map(\.id), ["favorite3", "favorite1"])
        XCTAssertEqual(rows.map(\.raw), [first, second])
    }
}
