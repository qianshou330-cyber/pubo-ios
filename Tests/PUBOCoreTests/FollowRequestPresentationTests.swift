import XCTest
@testable import PUBOCore

final class FollowRequestPresentationTests: XCTestCase {
    private func row(_ id: String) -> Record { Record(.object(["id": .string(id)])) }
    func testDirectionDefaultsAndEndpointsMirrorH5() {
        XCTAssertEqual(FollowRequestDirection.initial(user: .object(["isLocked": .bool(true)])), .received)
        XCTAssertEqual(FollowRequestDirection.initial(user: .object(["isLocked": .bool(false)])), .sent)
        XCTAssertEqual(FollowRequestDirection.received.endpoint, "following/requests/list")
        XCTAssertEqual(FollowRequestDirection.sent.endpoint, "following/requests/sent")
        XCTAssertEqual(FollowRequestDirection.sent.userKey, "followee")
    }
    func testDestructiveDecisionsRequireConfirmationAndCorrectDirection() {
        XCTAssertFalse(FollowRequestDecision.accept.requiresConfirmation)
        XCTAssertTrue(FollowRequestDecision.reject.requiresConfirmation)
        XCTAssertTrue(FollowRequestDecision.cancel.requiresConfirmation)
        XCTAssertTrue(FollowRequestDecision.cancel.allowed(in: .sent))
        XCTAssertFalse(FollowRequestDecision.cancel.allowed(in: .received))
        XCTAssertFalse(FollowRequestDecision.reject.allowed(in: .sent))
        XCTAssertEqual(FollowRequestDecision.cancel.endpoint, "following/requests/cancel")
    }
    func testHandlingEveryRowPreservesServerCursorForNextPage() {
        var state = FollowRequestPage()
        state.apply([row("03"), row("02")], reset: true, limit: 2)
        state.handled("03"); state.handled("02")
        XCTAssertTrue(state.rows.isEmpty); XCTAssertTrue(state.hasMore); XCTAssertEqual(state.cursor, "02")
        state.apply([row("01")], reset: false, limit: 2)
        XCTAssertEqual(state.rows.map(\.id), ["01"]); XCTAssertFalse(state.hasMore)
    }
    func testHandledRequestsDoNotReappearInStaleSnapshotButNewRequestsCan() {
        var state = FollowRequestPage()
        state.apply([row("02")], reset: true, limit: 2); state.handled("02")
        state.apply([row("03"), row("02")], reset: true, limit: 2)
        XCTAssertEqual(state.rows.map(\.id), ["03"])
    }
    func testDuplicateOrNonAdvancingPageDoesNotCreateAnEndlessLoadMoreLoop() {
        var state = FollowRequestPage()
        state.apply([row("03"), row("02")], reset: true, limit: 2)
        state.apply([row("03"), row("02")], reset: false, limit: 2)
        XCTAssertEqual(state.rows.count, 2); XCTAssertFalse(state.hasMore)
    }
}
