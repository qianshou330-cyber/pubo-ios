import XCTest
@testable import PUBOCore

final class SocialParityTests: XCTestCase {
    func testQuotesWithFilesOrPollAreNeverUnwrapped() {
        let original: JSONValue = .object(["id": .string("original"), "text": .string("原帖")])
        var value: [String: JSONValue] = ["id": .string("quote"), "text": .string(""), "renoteId": .string("original"), "renote": original]
        XCTAssertEqual(NoteContext.displayed(Record(.object(value))).id, "original")
        value["files"] = .array([.object(["id": .string("file")])])
        XCTAssertEqual(NoteContext.displayed(Record(.object(value))).id, "quote")
        value["files"] = .array([]); value["poll"] = .object(["choices": .array([])])
        XCTAssertFalse(NoteContext.isRepost(Record(.object(value))))
        value["poll"] = .null; value["text"] = .string("补充意见")
        XCTAssertFalse(NoteContext.isRepost(Record(.object(value))))
    }
    func testContextNeverRevealsCWOrHiddenText() {
        let cw = Record(.object(["id": .string("n"), "cw": .string("提示"), "text": .string("隐藏正文")]))
        XCTAssertEqual(NoteContext.summary(cw), "提示")
        XCTAssertEqual(NoteContext.summary(Record(.object(["isHidden": .bool(true), "text": .string("不可见正文")]))), "原帖不可见")
    }
    func testNotificationRoutingUsesRoomAndFileIDsNotSender() {
        let user: JSONValue = .object(["id": .string("sender")])
        let invitation = Record(.object(["type": .string("chatRoomInvitationReceived"), "user": user, "invitation": .object(["room": .object(["id": .string("room")])])]))
        XCTAssertEqual(NotificationTarget.resolve(invitation), .room("room"))
        XCTAssertEqual(NotificationTarget.resolve(Record(.object(["type": .string("chatRoomInvitationReceived"), "user": user]))), .none)
        XCTAssertEqual(NotificationTarget.resolve(Record(.object(["type": .string("exportCompleted"), "fileId": .string("file"), "url": .string("https://untrusted.invalid/")]))), .file("file"))
        XCTAssertEqual(NotificationTarget.resolve(Record(.object(["type": .string("exportCompleted"), "url": .string("https://untrusted.invalid/")]))), .none)
    }
    func testNotificationSecurityAndFallbackDestinations() {
        for (type, target) in [("login", NotificationTarget.sessions), ("createToken", .connections), ("receiveFollowRequest", .followRequests), ("achievementEarned", .achievements), ("scheduledNotePostFailed", .scheduled)] {
            XCTAssertEqual(NotificationTarget.resolve(Record(.object(["type": .string(type)]))), target)
        }
        XCTAssertEqual(NotificationTarget.resolve(Record(.object(["type": .string("newType")]))), .none)
    }
    func testLimitsMatchServerUnicodeScalarCounting() {
        XCTAssertNil(SendFeedback.limitError(String(repeating: "😀", count: 2000), limit: 2000))
        XCTAssertNotNil(SendFeedback.limitError(String(repeating: "😀", count: 2001), limit: 2000))
        XCTAssertNotNil(SendFeedback.limitError(String(repeating: "字", count: 101), limit: 100, label: "内容提示"))
    }
    func testInsertionReplacesSelectionAndPreservesUnicode() {
        var text = "前😀后"; var selection = NSRange(location: 1, length: 2)
        TextInsertion.insert("❤️", into: &text, selection: &selection)
        XCTAssertEqual(text, "前❤️后"); XCTAssertEqual(selection, NSRange(location: 3, length: 0))
        TextInsertion.insert("中", into: &text, selection: &selection); XCTAssertEqual(text, "前❤️中后")
        selection = NSRange(location: NSNotFound, length: 0); TextInsertion.insert("末", into: &text, selection: &selection); XCTAssertTrue(text.hasSuffix("末"))
    }
    func testRecallPrecedesAttachmentSummary() {
        let voice: JSONValue = .object(["attachments": .array([.object(["kind": .string("voice")])])])
        XCTAssertEqual(SendFeedback.messageSummary(voice), "[语音]")
        var recalled = voice.object; recalled["recalledAt"] = .string("now"); recalled["text"] = .string("旧内容")
        XCTAssertEqual(SendFeedback.messageSummary(.object(recalled)), "消息已撤回")
    }
}
