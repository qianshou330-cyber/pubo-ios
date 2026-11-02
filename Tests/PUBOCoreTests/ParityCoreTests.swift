import XCTest
@testable import PUBOCore

final class ParityCoreTests: XCTestCase {
    func testMovementUsesHistoryOnlyWhenSourceCannotCompare() {
        let row: JSONValue = .object(["sourceMovement": .object(["type": .string("unknown")]), "previousRank": .number(1), "change": .number(-1)])
        XCTAssertEqual(ChartMovement(row).label, "↓1")
        XCTAssertEqual(ChartMovement(row).basis, "本站上次可比较记录")
        var fields = row.object; fields["sourceMovement"] = .object(["type": .string("up"), "amount": .number(3)])
        XCTAssertEqual(ChartMovement(.object(fields)).label, "↑3")
        XCTAssertEqual(ChartMovement(.object(fields)).basis, "来源标注")
    }
    func testOnlyExplicitSourceCanMarkNewAndInvalidFieldsDoNotBecomeZero() {
        for value in [JSONValue.null, .object(["change": .number(0)]), .object(["sourceMovement": .object(["type": .string("up"), "amount": .number(0)])])] {
            XCTAssertEqual(ChartMovement(value).label, "—")
        }
        XCTAssertEqual(ChartMovement(.object(["sourceMovement": .object(["type": .string("new")])])).label, "NEW")
        XCTAssertEqual(ChartMovement(.object(["previousRank": .number(12), "change": .number(0)])).label, "＝")
        XCTAssertNil(ChartMovement.integer(.number(1.2)))
        XCTAssertNil(ChartMovement.integer(.string("3")))
    }
    func testPreferencesValidateAndRememberMelonWithoutChangingGroup() throws {
        var value = KpopPreferences(); value.groupID = "ive"; value.selectChart("melon-daily"); value.selectChart("spotify")
        XCTAssertEqual(value.lastMelonChart, "melon-daily"); XCTAssertEqual(value.groupID, "ive")
        value.selectChart("unknown"); XCTAssertEqual(value.chartKey, "spotify")
        value.groupID = "invalid"; value.lastMelonChart = "apple"
        let decoded = try JSONDecoder().decode(KpopPreferences.self, from: JSONEncoder().encode(value)).validated
        XCTAssertEqual(decoded.groupID, ""); XCTAssertEqual(decoded.lastMelonChart, "melon-top100")
    }
    func testOfficialHistoryUsesPeriodNotObservationAndBreaksGaps() {
        let points: [JSONValue] = [
            .object(["sourcePeriod": .string("2026-11-01"), "observedAt": .string("2026-11-02T02:00:00Z"), "result": .string("ranked"), "rank": .number(10)]),
            .object(["sourcePeriod": .string("2026-11-02"), "result": .string("missing")]),
            .object(["sourcePeriod": .string("2026-11-03"), "result": .string("ranked"), "rank": .number(9)]),
            .object(["observedAt": .string("2026-11-04T02:00:00Z"), "result": .string("ranked"), "rank": .number(1)])]
        let result = ChartHistoryPoint.parse(.object(["basis": .string("official_period"), "points": .array(points)]))
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].date, SocialContent.date("2026-10-31T15:00:00Z"))
        XCTAssertNil(result[1].rank); XCTAssertNotEqual(result[0].segment, result[2].segment)
    }
    func testHistoricalQuoteChangesWithoutAddingTargetToVisiblePage() {
        let target = message("target", 2, "edited")
        let reply = quoting("reply", target: message("target", 1, "old"))
        let result = ChatReferences.reconcile([reply], targets: [target])
        XCTAssertEqual(result.map(\.id), ["reply"])
        XCTAssertEqual(result[0]["replyTo"]["text"].string, "edited")
        XCTAssertEqual(ChatReferences.ids(result), Set(["target"]))
    }
    func testRecalledQuoteCannotBeResurrectedByOldParentOrTarget() {
        let oldTarget = message("target", 1, "private old text")
        let oldReply = quoting("reply", target: oldTarget)
        let recalled = message("target", 2, "", recalled: true)
        let result = ChatReferences.reconcile([oldReply], targets: [recalled])
        XCTAssertEqual(ChatReferences.label(result[0]["replyTo"]), "原消息已撤回")
        XCTAssertTrue(result[0]["replyTo"]["text"].isNull)
        let late = ChatRecords.merge(result, [oldReply])
        XCTAssertEqual(ChatReferences.label(late[0]["replyTo"]), "原消息已撤回")
        XCTAssertEqual(ChatReferences.reconcile(late, targets: [oldTarget]), late)
    }
    func testMissingReferenceAndAttachmentOnlyReferenceHaveVisibleExplanation() {
        var target = message("target", 0, "").raw.object
        target["attachments"] = .array([.object(["kind": .string("voice")])])
        let reply = quoting("reply", target: Record(.object(target)))
        XCTAssertEqual(ChatReferences.label(reply["replyTo"]), "语音")
        let result = ChatReferences.reconcile([reply], targets: [], missing: ["target"])
        XCTAssertEqual(ChatReferences.label(result[0]["replyTo"]), "原消息暂不可用")
        XCTAssertTrue(result[0]["replyTo"]["text"].isNull)
    }
    func testMutedRawUnreadDoesNotCreateAnEntryBadge() throws {
        var badge = NotificationBadges()
        try badge.applyChat(.object(["unreadCount": .number(99), "notificationUnreadCount": .number(0), "hasNotificationLegacyUnread": .bool(false), "hasUnreadRoom": .bool(false)]))
        XCTAssertNil(badge.chatLabel)
        try badge.applyChat(.object(["notificationUnreadCount": .number(101), "hasNotificationLegacyUnread": .bool(false), "hasUnreadRoom": .bool(true)]))
        XCTAssertEqual(badge.chatLabel, "99+")
        XCTAssertThrowsError(try badge.applyChat(.null)); XCTAssertEqual(badge.chatLabel, "99+")
    }
    private func message(_ id: String, _ revision: Int, _ text: String, recalled: Bool = false) -> Record {
        Record(.object(["id": .string(id), "fromUserId": .string("peer"), "revision": .number(Double(revision)), "text": .string(text), "recalledAt": recalled ? .string("2026-11-02T00:00:00Z") : .null]))
    }
    private func quoting(_ id: String, target: Record) -> Record {
        Record(.object(["id": .string(id), "revision": .number(0), "replyToId": .string(target.id), "replyTo": ChatReferences.summary(target)]))
    }
}
