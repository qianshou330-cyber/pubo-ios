import XCTest
@testable import PUBOCore

final class AppNavigationTests: XCTestCase {
    func testApprovedTabOrderAndLabels() {
        XCTAssertEqual(AppTab.allCases, [.messages, .friends, .world, .me])
        XCTAssertEqual(AppTab.allCases.map(\.title), ["消息", "好友", "世界圈", "我的"])
    }
    func testPushDestinationsHaveSeparateOwners() {
        XCTAssertEqual(AppRoute.chat(userID: "friend").tab, .messages)
        XCTAssertEqual(AppRoute.room("room").tab, .messages)
        XCTAssertEqual(AppRoute.note("note").tab, .world)
        XCTAssertEqual(AppRoute.followRequests.tab, .friends)
        XCTAssertEqual(AppRoute.notifications.tab, .me)
    }
    func testSwitchAndReloginRejectStaleNavigation() {
        let epoch = UUID()
        XCTAssertTrue(AppNavigationPolicy.canRoute(owner: "a", generation: epoch, currentOwner: "a", currentGeneration: epoch))
        XCTAssertFalse(AppNavigationPolicy.canRoute(owner: "a", generation: epoch, currentOwner: "b", currentGeneration: epoch))
        XCTAssertFalse(AppNavigationPolicy.canRoute(owner: "a", generation: epoch, currentOwner: "a", currentGeneration: UUID()))
        XCTAssertFalse(AppNavigationPolicy.canRoute(owner: "a", generation: epoch, currentOwner: nil, currentGeneration: epoch))
    }
    func testNotificationTypesDoNotAllGoToMessages() {
        XCTAssertEqual(AppNavigationPolicy.notificationRoute(.object(["type": .string("receiveFollowRequest")])), .followRequests)
        XCTAssertEqual(AppNavigationPolicy.notificationRoute(.object(["type": .string("reaction"), "note": .object(["id": .string("note1")])])), .note("note1"))
        XCTAssertEqual(AppNavigationPolicy.notificationRoute(.object(["type": .string("announcement")])), .notifications)
    }
    func testReadingNotificationsDoesNotClearChatBadge() throws {
        var badges = NotificationBadges()
        try badges.applyChat(.object(["notificationUnreadCount": .number(5), "hasNotificationLegacyUnread": .bool(false), "hasUnreadRoom": .bool(false)]))
        badges.applyAccount(.object(["hasUnreadNotification": .bool(true), "unreadNotificationsCount": .number(2)]))
        badges.markNotificationsRead()
        XCTAssertNil(badges.notificationLabel)
        XCTAssertEqual(badges.chatLabel, "5")
    }
}
