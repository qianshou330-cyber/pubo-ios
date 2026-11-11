import XCTest
@testable import PUBOCore

final class ContactMemberPageTests: XCTestCase {
    private func user(_ id: String) -> JSONValue { .object(["id": .string(id), "name": .string(id)]) }
    func testPaginationFollowsRequestedIDsNotMissingUsers() throws {
        var page = ContactMemberPage(ids: (1...51).map(String.init))
        let requested = page.nextIDs
        XCTAssertEqual(requested.count, 50)
        XCTAssertFalse(try page.apply(.array(requested.dropFirst().reversed().map(user)), requested: requested))
        XCTAssertEqual(page.offset, 50); XCTAssertEqual(page.rows.first?.id, "2")
        XCTAssertEqual(page.nextIDs, ["51"])
        XCTAssertTrue(try page.apply(.array([user("51")]), requested: ["51"]))
        XCTAssertFalse(page.hasMore); XCTAssertEqual(page.rows.last?.id, "51")
    }
    func testInvalidResponseDoesNotAdvanceOrDestroySnapshot() throws {
        var page = ContactMemberPage(ids: ["a", "b"])
        for response in [JSONValue.object([:]), .array([user("other")]), .array([user("a"), user("a")]), .array([.object([:])])] {
            XCTAssertThrowsError(try page.apply(response, requested: ["a", "b"]))
            XCTAssertEqual(page.offset, 0); XCTAssertTrue(page.rows.isEmpty)
        }
        XCTAssertThrowsError(try page.apply(.array([user("a")]), requested: ["a"]))
    }
    func testDeduplicateIDsAndAdvanceEntireUnavailableBatch() throws {
        var page = ContactMemberPage(ids: ["a", "", "a", "b"])
        XCTAssertEqual(page.ids, ["a", "b"])
        XCTAssertFalse(try page.apply(.array([]), requested: ["a", "b"]))
        XCTAssertEqual(page.offset, 2); XCTAssertFalse(page.hasMore)
    }
    func testRefreshCandidateDoesNotMutatePublishedPageUntilCommitted() throws {
        var published = ContactMemberPage(ids: ["old"])
        try published.apply(.array([user("old")]), requested: ["old"])
        var candidate = ContactMemberPage(ids: ["new"])
        XCTAssertThrowsError(try candidate.apply(.object([:]), requested: ["new"]))
        XCTAssertEqual(published.rows.map(\.id), ["old"])
        try candidate.apply(.array([user("new")]), requested: ["new"])
        published = candidate
        XCTAssertEqual(published.rows.map(\.id), ["new"])
    }
}
