import XCTest
@testable import PUBOCore

final class ChatEligibilityTests: XCTestCase {
    private func account(_ policy: String) -> Record {
        Record(.object(["policies": .object(["chatAvailability": .string(policy)])]))
    }
    func testAvailableReadonlyUnavailableAndUnknownPolicies() {
        XCTAssertNil(ChatEligibility.problem(account: account("available")))
        XCTAssertTrue(ChatEligibility.problem(account: account("readonly"))!.contains("只读"))
        XCTAssertTrue(ChatEligibility.problem(account: account("unavailable"))!.contains("暂不可"))
        XCTAssertNotNil(ChatEligibility.problem(account: account("new-policy")))
        XCTAssertNotNil(ChatEligibility.problem(account: nil))
        XCTAssertNotNil(ChatEligibility.problem(account: Record(.object([:]))))
    }
    func testRemoteAndDisabledPeersAreBlockedButLightweightRecordIsNotFalse() {
        let available = account("available")
        XCTAssertNotNil(ChatEligibility.problem(account: available, peer: Record(.object(["host": .string("example.org"), "canChat": .bool(true)]))))
        XCTAssertNotNil(ChatEligibility.problem(account: available, peer: Record(.object(["host": .null, "canChat": .bool(false)]))))
        XCTAssertNil(ChatEligibility.problem(account: available, peer: Record(.object(["host": .null, "canChat": .bool(true)]))))
        XCTAssertNil(ChatEligibility.problem(account: available, peer: Record(.object(["id": .string("lite")]))))
    }
    func testAccountRestrictionPrecedesPeerRestriction() {
        XCTAssertTrue(ChatEligibility.problem(account: account("readonly"), peer: Record(.object(["canChat": .bool(false)])))!.contains("只读"))
    }
    func testSearchIncomingOutgoingRoomAndFallbackIdentities() {
        let message = Record(.object([
            "fromUserId": .string("alice"), "toUserId": .string("bob"),
            "fromUser": .object(["name": .string("Alice"), "username": .string("alice")]),
            "toUser": .object(["username": .string("bob")]),
        ]))
        XCTAssertEqual(ChatSearchPresentation.sender(message, viewerID: "alice"), "你")
        XCTAssertEqual(ChatSearchPresentation.sender(message, viewerID: "bob"), "Alice @alice")
        XCTAssertEqual(ChatSearchPresentation.destination(message, viewerID: "alice"), "私信 · @bob")
        XCTAssertEqual(ChatSearchPresentation.destination(message, viewerID: "bob"), "私信 · Alice @alice")
        let room = Record(.object(["toRoomId": .string("r1"), "toRoom": .object(["name": .string("群一")])]))
        XCTAssertEqual(ChatSearchPresentation.destination(room, viewerID: "alice"), "群聊 · 群一")
        XCTAssertEqual(ChatSearchPresentation.destination(Record(.object(["toRoomId": .string("r2")])), viewerID: nil), "群聊 · r2")
        XCTAssertEqual(ChatSearchPresentation.sender(Record(.object(["fromUserId": .string("deleted")])), viewerID: nil), "deleted")
    }
    func testSearchEmptyOnlyAfterSuccessfulCompletedRequest() {
        XCTAssertTrue(ChatSearchPresentation.showsEmpty(completed: true, busy: false, hasError: false, count: 0))
        XCTAssertFalse(ChatSearchPresentation.showsEmpty(completed: false, busy: false, hasError: false, count: 0))
        XCTAssertFalse(ChatSearchPresentation.showsEmpty(completed: true, busy: true, hasError: false, count: 0))
        XCTAssertFalse(ChatSearchPresentation.showsEmpty(completed: true, busy: false, hasError: true, count: 0))
        XCTAssertFalse(ChatSearchPresentation.showsEmpty(completed: true, busy: false, hasError: false, count: 1))
    }
}
