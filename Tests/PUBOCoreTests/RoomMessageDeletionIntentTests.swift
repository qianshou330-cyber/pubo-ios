import XCTest
@testable import PUBOCore

final class RoomMessageDeletionIntentTests: XCTestCase {
    private let epoch = UUID()
    private let screen = UUID()
    private func message(id: String = "m1", owner: String = "alice", room: String = "r1", recalled: Bool = false) -> Record {
        Record(.object(["id": .string(id), "fromUserId": .string(owner), "toRoomId": .string(room), "recalledAt": recalled ? .string("2026-11-14") : .null]))
    }
    private func intent() -> RoomMessageDeletionIntent {
        RoomMessageDeletionIntent(ownerID: "alice", generation: epoch, screenID: screen, roomID: "r1", message: message())!
    }
    func testCurrentOwnMessageIsPermitted() {
        XCTAssertTrue(intent().matches(ownerID: "alice", generation: epoch, screenID: screen, roomID: "r1", active: true))
        XCTAssertTrue(intent().permits(message()))
    }
    func testForeignRecalledMissingOrWrongRoomCannotCreateConfirmation() {
        for record in [message(owner: "bob"), message(room: "r2"), message(recalled: true), message(id: "")] {
            XCTAssertNil(RoomMessageDeletionIntent(ownerID: "alice", generation: epoch, screenID: screen, roomID: "r1", message: record))
        }
    }
    func testAccountSwitchAndLogoutInvalidateIntent() {
        XCTAssertFalse(intent().matches(ownerID: "bob", generation: epoch, screenID: screen, roomID: "r1", active: true))
        XCTAssertFalse(intent().matches(ownerID: nil, generation: epoch, screenID: screen, roomID: "r1", active: true))
    }
    func testSwitchAwayAndBackToSameAccountStillInvalidatesIntent() {
        XCTAssertFalse(intent().matches(ownerID: "alice", generation: UUID(), screenID: screen, roomID: "r1", active: true))
    }
    func testNavigationAndScreenReuseInvalidateIntent() {
        XCTAssertFalse(intent().matches(ownerID: "alice", generation: epoch, screenID: UUID(), roomID: "r1", active: true))
        XCTAssertFalse(intent().matches(ownerID: "alice", generation: epoch, screenID: screen, roomID: "r2", active: true))
        XCTAssertFalse(intent().matches(ownerID: "alice", generation: epoch, screenID: screen, roomID: "r1", active: false))
    }
    func testChangedDeletedOrRecalledMessageCannotBeSubmitted() {
        for record in [message(id: "m2"), message(owner: "bob"), message(room: "r2"), message(recalled: true)] {
            XCTAssertFalse(intent().permits(record))
        }
        XCTAssertFalse(intent().permits(nil))
    }
    func testUnrelatedReactionOrTextChangesDoNotRetargetDeletion() {
        var fields = message().raw.object
        fields["text"] = .string("edited text")
        fields["reactions"] = .array([.string("heart")])
        XCTAssertTrue(intent().permits(Record(.object(fields))))
    }
}
