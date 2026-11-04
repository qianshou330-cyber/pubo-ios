import XCTest
@testable import PUBOCore

final class ChatPresentationTests: XCTestCase {
    private func user(_ id: String, time: String, pin: String? = nil, unread: Int = 0) -> ChatConversation {
        ChatConversation.direct(.object(["user": .object(["id": .string(id)]), "lastMessage": .object(["id": .string("m-" + id), "createdAt": .string(time)]), "pinnedAt": pin.map(JSONValue.string) ?? .null, "unreadCount": .number(Double(unread))]))!
    }
    private func room(_ id: String, time: String, read: Bool = false) -> ChatConversation {
        ChatConversation.room(.object(["id": .string("r-" + id), "toRoomId": .string(id), "toRoom": .object(["id": .string(id)]), "fromUserId": .string("other"), "createdAt": .string(time), "isRead": .bool(read)]), viewer: "me")!
    }
    func testMixedIDsPinOrderAndStableChronologicalOrder() {
        let list = ChatConversation.merge([], ordinary: [user("same", time: "2026-11-04"), user("old", time: "2026-10-01")], pins: [user("pin1", time: "2025", pin: "2026-11-03"), user("pin2", time: "2024", pin: "2026-11-04")], rooms: [room("same", time: "2026-11-05")])
        XCTAssertEqual(list.map(\.id), ["user:pin2", "user:pin1", "room:same", "user:same", "user:old"])
    }
    func testRefreshPreservesDirectHistoryAndReplacesOnlySuccessfulRoomSnapshot() {
        let old = [user("older-page", time: "1"), user("latest", time: "3"), room("old-room", time: "2")]
        let failed = ChatConversation.merge(old, ordinary: [user("latest", time: "4")], pins: nil, rooms: nil)
        XCTAssertEqual(Set(failed.map(\.id)), Set(old.map(\.id)))
        let refreshed = ChatConversation.merge(failed, ordinary: [], pins: [], rooms: [room("new-room", time: "5")])
        XCTAssertEqual(refreshed.map(\.id), ["room:new-room", "user:latest", "user:older-page"])
    }
    func testUnpinPreservesOlderConversationAndNeverPinsRooms() {
        let old = [user("old", time: "1", pin: "4"), room("group", time: "3")]
        let list = ChatConversation.merge(old, ordinary: [], pins: [], rooms: nil)
        XCTAssertEqual(list.map(\.id), ["room:group", "user:old"]); XCTAssertNil(list.last?.pinnedAt)
    }
    func testUnreadUsesRealCountsAndUnknownRoomDot() {
        XCTAssertEqual(user("a", time: "1", unread: 120).badge, "99+")
        XCTAssertNil(room("r", time: "1").badge); XCTAssertTrue(room("r", time: "1").legacyUnread)
        XCTAssertFalse(room("r", time: "1", read: true).legacyUnread)
    }
    func testReactionIdentityAndClickingAnotherDuplicateNeverCancelsMine() {
        let values: [JSONValue] = ["me", "other", "other"].map { .object(["user": .object(["id": .string($0)]), "reaction": .string("❤")]) }
        let rows = ChatReaction.rows(values)
        XCTAssertEqual(rows.count, 2); XCTAssertTrue(rows[0].isActionable(viewer: "me", all: rows))
        XCTAssertFalse(rows[1].isActionable(viewer: "me", all: rows))
        XCTAssertTrue(rows[1].isActionable(viewer: "me", all: [rows[1]]))
    }
    func testLocalDateBoundaryIncludingYearDoesNotDependOnUTCDay() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        func message(_ date: String) -> Record { Record(.object(["id": .string(date), "createdAt": .string(date)])) }
        XCTAssertNil(ChatDays.separator(previous: nil, current: message("2026-11-04T00:00:00Z"), calendar: calendar))
        XCTAssertNil(ChatDays.separator(previous: message("2026-11-03T17:00:00Z"), current: message("2026-11-04T02:00:00Z"), calendar: calendar))
        XCTAssertEqual(ChatDays.separator(previous: message("2026-12-31T15:59:00Z"), current: message("2026-12-31T16:01:00.000Z"), calendar: calendar), "2026/12/31 · 2027/1/1")
    }
}
