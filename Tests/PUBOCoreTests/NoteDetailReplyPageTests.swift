import Foundation
import XCTest
@testable import PUBOCore

final class NoteDetailReplyPageTests: XCTestCase {
    private func row(_ id: Int, text: String = "reply") -> JSONValue {
        .object(["id": .string(String(format: "reply%03d", id)), "text": .string(text)])
    }

    private func fullPage() -> [JSONValue] {
        (31...60).reversed().map { row($0) }
    }

    func testUnrequestedAndConfirmedEmptyHaveNoOlderCursor() throws {
        var page = NoteDetailReplyPage()
        XCTAssertEqual(NoteDetailReplyPage.limit, 30)
        XCTAssertTrue(page.rows.isEmpty)
        XCTAssertNil(page.olderCursor)
        try page.apply(.array([]), older: false)
        XCTAssertTrue(page.rows.isEmpty)
        XCTAssertNil(page.olderCursor)
    }

    func testShortOrMixedPageKeepsOriginalAcceptedOrderAndRawFields() throws {
        var page = NoteDetailReplyPage()
        let hidden = JSONValue.object(["id": .string("reply030"), "isHidden": .bool(true),
                                       "cw": .null, "futureField": .object(["opaque": .bool(true)])])
        let items = [hidden, .null] + (31...58).map { row($0) }
        XCTAssertEqual(items.count, 30)
        try page.apply(.array(items), older: false)
        XCTAssertEqual(page.rows.map(\.raw), items.filter { !$0.isNull })
        XCTAssertEqual(page.rows.count, 29)
        XCTAssertNil(page.olderCursor, "Preserve the accepted-record page-size rule.")
    }

    func testFullPageUsesLastAcceptedIDAndShortTailUsesOriginalMerge() throws {
        var page = NoteDetailReplyPage()
        let first = fullPage()
        try page.apply(.array(first), older: false)
        XCTAssertEqual(page.rows.map(\.raw), first)
        XCTAssertEqual(page.olderCursor, "reply031")

        let tail = [row(31, text: "replacement"), row(30)]
        try page.apply(.array(tail), older: true)
        XCTAssertEqual(page.rows.map(\.raw), Array(first.dropLast()) + tail)
        XCTAssertNil(page.olderCursor)
    }

    func testSuccessfulEmptyOlderTailRetainsRowsButEndsPaging() throws {
        var page = NoteDetailReplyPage()
        let first = fullPage()
        try page.apply(.array(first), older: false)
        XCTAssertEqual(page.olderCursor, "reply031")
        try page.apply(.array([]), older: true)
        XCTAssertEqual(page.rows.map(\.raw), first)
        XCTAssertNil(page.olderCursor)
    }

    func testMalformedInitialPageDoesNotEnableOlder() throws {
        var page = NoteDetailReplyPage()
        let invalid: [JSONValue] = [.null, .object(["items": .array([])]),
                                    .array([.null, .object(["text": .string("not identifiable")])])]
        for response in invalid {
            XCTAssertThrowsError(try page.apply(response, older: false)) { error in
                XCTAssertEqual((error as? APIError)?.code, "INVALID_RESPONSE")
            }
            XCTAssertTrue(page.rows.isEmpty)
            XCTAssertNil(page.olderCursor)
        }
    }

    func testMalformedRefreshOrOlderPagePreservesRowsAndCursor() throws {
        var page = NoteDetailReplyPage()
        let first = fullPage()
        try page.apply(.array(first), older: false)
        for older in [false, true] {
            for response in [JSONValue.null, .array([.object(["id": .number(1)])])] {
                XCTAssertThrowsError(try page.apply(response, older: older))
                XCTAssertEqual(page.rows.map(\.raw), first)
                XCTAssertEqual(page.olderCursor, "reply031")
            }
        }

        try page.apply(.array([]), older: false)
        XCTAssertTrue(page.rows.isEmpty)
        XCTAssertNil(page.olderCursor)
    }
}
