import XCTest
@testable import PUBOCore

final class ChatForwardPolicyTests: XCTestCase {
    private func makeMessage(
        id: String,
        from: String = "syntheticpeer",
        text: String = "消息内容",
        recalled: Bool = false,
        attachments: [JSONValue] = [],
        fallback: Bool = false
    ) -> Record {
        var obj: [String: JSONValue] = [
            "id": .string(id),
            "fromUserId": .string(from),
            "text": .string(text),
            "attachments": .array(attachments),
            "privateAttachmentFallback": .bool(fallback)
        ]
        if recalled { obj["recalledAt"] = .string("2026-11-27T00:00:00Z") }
        return Record(.object(obj))
    }

    private func makeUser(id: String, username: String, name: String, host: String? = nil, canChat: Bool? = nil) -> Record {
        var obj: [String: JSONValue] = [
            "id": .string(id),
            "username": .string(username),
            "name": .string(name),
            "host": host.map(JSONValue.string) ?? .null
        ]
        if let canChat { obj["canChat"] = .bool(canChat) }
        return Record(.object(obj))
    }

    private var availableAccount: Record {
        Record(.object([
            "id": .string("syntheticself"),
            "username": .string("fixture"),
            "name": .string("测试用户"),
            "policies": .object(["chatAvailability": .string("available")])
        ]))
    }

    func testSelectionCapsAtTenAndBlocksEleventhMessage() {
        var state = ChatSelectionState()
        let timeline = (1...12).map { makeMessage(id: String(format: "msg%02d", $0), text: "第 \($0) 条") }

        for index in 0..<10 {
            XCTAssertEqual(state.toggle(timeline[index]), .selected(count: index + 1))
        }
        XCTAssertTrue(state.isAtLimit)
        XCTAssertEqual(state.count, 10)

        // 11th message must be rejected without modifying the existing 10 selections.
        XCTAssertEqual(state.toggle(timeline[10]), .limitReached(max: 10))
        XCTAssertEqual(state.count, 10)
        XCTAssertFalse(state.contains("msg11"))

        // Deselecting one message allows selecting the 11th message.
        XCTAssertEqual(state.toggle(timeline[0]), .deselected(count: 9))
        XCTAssertFalse(state.isAtLimit)
        XCTAssertEqual(state.toggle(timeline[10]), .selected(count: 10))
        XCTAssertTrue(state.contains("msg11"))
    }

    func testSelectionRejectsRecalledAndPrunesChronologically() {
        var state = ChatSelectionState()
        let recalled = makeMessage(id: "recalled1", text: "", recalled: true)
        XCTAssertEqual(state.toggle(recalled), .ineligibleRecalled)
        XCTAssertTrue(state.isEmpty)

        let m1 = makeMessage(id: "m1", text: "第一条")
        let m2 = makeMessage(id: "m2", text: "第二条")
        let m3 = makeMessage(id: "m3", text: "第三条")
        // User taps out of chronological order (m3 then m1 then m2).
        XCTAssertEqual(state.toggle(m3), .selected(count: 1))
        XCTAssertEqual(state.toggle(m1), .selected(count: 2))
        XCTAssertEqual(state.toggle(m2), .selected(count: 3))

        // Suppose m2 gets recalled remotely; pruneAndOrdered drops m2 and returns [m1, m3] in timeline order.
        let updatedTimeline = [m1, makeMessage(id: "m2", text: "", recalled: true), m3]
        let ordered = state.pruneAndOrdered(from: updatedTimeline)
        XCTAssertEqual(ordered.map(\.id), ["m1", "m3"])
        XCTAssertEqual(state.count, 2)
        XCTAssertFalse(state.contains("m2"))
    }

    func testRecipientEligibilityBlocksSelfRemoteAndUnavailablePeer() {
        let localFriend = makeUser(id: "syntheticfriend2", username: "friend2", name: "测试好友二")
        XCTAssertNil(ChatForwardPlanner.eligibleRecipientProblem(account: availableAccount, viewerID: "syntheticself", recipient: localFriend))

        let myself = makeUser(id: "syntheticself", username: "fixture", name: "测试用户")
        XCTAssertEqual(
            ChatForwardPlanner.eligibleRecipientProblem(account: availableAccount, viewerID: "syntheticself", recipient: myself),
            "不能转发消息给自己。"
        )

        let remote = makeUser(id: "remote1", username: "bob", name: "外站用户", host: "other.example")
        XCTAssertNotNil(ChatForwardPlanner.eligibleRecipientProblem(account: availableAccount, viewerID: "syntheticself", recipient: remote))

        let disabledPeer = makeUser(id: "nochat", username: "quiet", name: "关闭聊天", canChat: false)
        XCTAssertNotNil(ChatForwardPlanner.eligibleRecipientProblem(account: availableAccount, viewerID: "syntheticself", recipient: disabledPeer))
    }

    func testCombinedTextFormattingAnd2000CharLimit() throws {
        let m1 = makeMessage(id: "m1", from: "syntheticpeer", text: "晚上吃什么？")
        let m2 = makeMessage(
            id: "m2",
            from: "syntheticself",
            text: "",
            attachments: [.object(["id": .string("att1"), "mime": .string("image/jpeg"), "size": .number(1024)])]
        )
        let combined = try ChatForwardPlanner.buildCombinedText(
            messages: [m1, m2],
            peerName: "测试朋友",
            viewerID: "syntheticself",
            viewerName: "测试用户"
        ).get()
        XCTAssertTrue(combined.contains("转发自与 测试朋友 的聊天记录（2 条）："))
        XCTAssertTrue(combined.contains("「测试朋友」晚上吃什么？"))
        XCTAssertTrue(combined.contains("「测试用户」[图片]"))

        let huge = makeMessage(id: "huge", from: "syntheticpeer", text: String(repeating: "字", count: 2_001))
        let failure = ChatForwardPlanner.buildCombinedText(
            messages: [huge],
            peerName: "测试朋友",
            viewerID: "syntheticself",
            viewerName: "测试用户"
        )
        guard case .failure(.combinedTooLong(let actual, let limit)) = failure else {
            return XCTFail("Expected combinedTooLong error")
        }
        XCTAssertGreaterThan(actual, limit)
        XCTAssertEqual(limit, 2_000)
    }

    func testCopyTextSingleAndMultipleMessages() {
        let m1 = makeMessage(id: "m1", from: "syntheticpeer", text: "第一句")
        let m2 = makeMessage(id: "m2", from: "syntheticself", text: "第二句")
        let single = ChatForwardPlanner.buildCopyText(messages: [m1], peerName: "测试朋友", viewerID: "syntheticself", viewerName: "测试用户")
        XCTAssertEqual(single, "第一句")

        let multi = ChatForwardPlanner.buildCopyText(messages: [m1, m2], peerName: "测试朋友", viewerID: "syntheticself", viewerName: "测试用户")
        XCTAssertEqual(multi, "测试朋友：第一句\n测试用户：第二句")
    }

    func testInspectAttachmentsCountsNormalOversizeFallbackAndVoice() {
        let msgs = [
            makeMessage(
                id: "m1",
                attachments: [
                    .object(["id": .string("a1"), "mime": .string("image/png"), "size": .number(10_000)]),
                    .object(["id": .string("a2"), "kind": .string("voice"), "mime": .string("audio/mp4"), "size": .number(20_000)]),
                    .object(["id": .string("a3"), "mime": .string("video/mp4"), "size": .number(60 * 1024 * 1024)])
                ]
            ),
            makeMessage(id: "m2", fallback: true)
        ]
        let summary = ChatForwardPlanner.inspectAttachments(in: msgs)
        XCTAssertEqual(summary.totalAttachments, 3)
        XCTAssertEqual(summary.oversizeCount, 1)
        XCTAssertEqual(summary.forwardableCount, 2)
        XCTAssertEqual(summary.voiceCount, 1)
        XCTAssertEqual(summary.fallbackCount, 1)
        XCTAssertTrue(summary.hasForwardableAttachments)
        XCTAssertTrue(summary.hasSkippedAttachments)
    }

    func testDeduplicateRecipientsRemovesSelfDuplicatesAndFiltersQuery() {
        let selfUser = makeUser(id: "syntheticself", username: "fixture", name: "测试用户")
        let friend1 = makeUser(id: "syntheticpeer", username: "friend", name: "测试朋友")
        let friend2 = makeUser(id: "syntheticfriend2", username: "friend2", name: "测试好友二")

        let all = ChatForwardPlanner.deduplicateRecipients(
            recent: [selfUser, friend1],
            following: [friend1, friend2, selfUser],
            viewerID: "syntheticself",
            query: ""
        )
        XCTAssertEqual(all.recent.map(\.id), ["syntheticpeer"])
        XCTAssertEqual(all.following.map(\.id), ["syntheticfriend2"])

        let filtered = ChatForwardPlanner.deduplicateRecipients(
            recent: [friend1],
            following: [friend2],
            viewerID: "syntheticself",
            query: "好友二"
        )
        XCTAssertTrue(filtered.recent.isEmpty)
        XCTAssertEqual(filtered.following.map(\.id), ["syntheticfriend2"])
    }
}
