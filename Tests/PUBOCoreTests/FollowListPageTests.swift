import XCTest
@testable import PUBOCore

final class FollowListPageTests: XCTestCase {
    private func row(_ id: String, name: String = "test", followers: Bool = false) -> JSONValue {
        .object(["id": .string(id), (followers ? "follower" : "followee"): .object(["id": .string("user-" + id), "name": .string(name)])])
    }
    func testFirstAndOlderPagesKeepOrderAndUpdateDuplicates() throws {
        var page = FollowListPage()
        try page.apply(.array([row("03"), row("02")]), reset: true, followers: false, limit: 2)
        XCTAssertTrue(page.hasMore); XCTAssertEqual(page.cursor, "02")
        try page.apply(.array([row("02", name: "updated"), row("01")]), reset: false, followers: false, limit: 2)
        XCTAssertEqual(page.rows.map(\.id), ["03", "02", "01"])
        XCTAssertEqual(page.rows[1]["followee"]["name"].string, "updated")
        try page.apply(.array([]), reset: false, followers: false, limit: 2)
        XCTAssertFalse(page.hasMore)
    }
    func testInvalidResponsePreservesPriorRowsAndCursor() throws {
        var page = FollowListPage()
        try page.apply(.array([row("02")]), reset: true, followers: false, limit: 1)
        XCTAssertThrowsError(try page.apply(.object([:]), reset: true, followers: false, limit: 1))
        XCTAssertThrowsError(try page.apply(.array([.object([:])]), reset: false, followers: false, limit: 1))
        XCTAssertEqual(page.rows.map(\.id), ["02"]); XCTAssertEqual(page.cursor, "02")
    }
    func testFollowersSelectCorrectUserAndSkipUnavailableUserWithoutLosingCursor() throws {
        var page = FollowListPage()
        try page.apply(.array([row("03", followers: true), .object(["id": .string("02"), "follower": .null])]), reset: true, followers: true, limit: 2)
        XCTAssertEqual(page.rows.map(\.id), ["03"]); XCTAssertEqual(page.cursor, "02"); XCTAssertTrue(page.hasMore)
    }
    func testRefreshReplacesAndRepeatedCursorStops() throws {
        var page = FollowListPage()
        try page.apply(.array([row("02")]), reset: true, followers: false, limit: 1)
        try page.apply(.array([row("02")]), reset: false, followers: false, limit: 1)
        XCTAssertFalse(page.hasMore)
        try page.apply(.array([row("04")]), reset: true, followers: false, limit: 1)
        XCTAssertEqual(page.rows.map(\.id), ["04"]); XCTAssertTrue(page.hasMore)
    }
}
