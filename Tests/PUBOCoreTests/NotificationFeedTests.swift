import XCTest
@testable import PUBOCore

final class NotificationFeedTests: XCTestCase {
    func testChangingBackBeforeTheNextCategoryLoadsRequiresARequest() {
        var state = NotificationRefreshState()
        state.didLoad("all", revision: state.revision)
        state.clearDisplayedQuery()
        XCTAssertNil(state.loadedQuery)
        XCTAssertNotEqual(state.loadedQuery, "all", "The emptied list cannot be reused as an all-tab result")
    }

    func testReconnectDuringFetchStaysPendingUntilTopIsRefetched() {
        var state = NotificationRefreshState()
        let initialRevision = state.revision
        state.invalidate()
        state.didLoad("all", revision: initialRevision)
        XCTAssertFalse(state.shouldRefresh("all", atTop: false))
        XCTAssertFalse(state.shouldRefresh("mentions", atTop: true))
        XCTAssertTrue(state.shouldRefresh("all", atTop: true))
        state.didLoad("all", revision: state.revision)
        XCTAssertFalse(state.shouldRefresh("all", atTop: true))
    }

    func testTabsUseTheirOwnEndpointsAndParameters() {
        XCTAssertEqual(NotificationTab.all.endpoint, "i/notifications-grouped")
        XCTAssertEqual(NotificationTab.all.parameters(filter: .reaction, until: "older"), [
            "limit": .number(20), "includeTypes": .strings(["reaction"]), "untilId": .string("older")
        ])
        XCTAssertEqual(NotificationTab.mentions.endpoint, "notes/mentions")
        XCTAssertEqual(NotificationTab.directNotes.endpoint, "notes/mentions")
        XCTAssertEqual(NotificationTab.mentions.parameters(filter: .follow, until: nil), ["limit": .number(10)])
        XCTAssertEqual(NotificationTab.directNotes.parameters(filter: .follow, until: nil), ["limit": .number(10), "visibility": .string("specified")])
        let date = Date(timeIntervalSince1970: 123)
        XCTAssertEqual(NotificationTab.mentions.parameters(filter: nil, until: nil, oldestFirst: true)["sinceId"], .string("0"))
        XCTAssertEqual(NotificationTab.mentions.parameters(filter: nil, until: nil, oldestFirst: true, date: date)["sinceDate"], .number(123000))
        XCTAssertEqual(NotificationTab.mentions.parameters(filter: nil, until: nil, date: date)["untilDate"], .number(123000))
        XCTAssertEqual(NotificationTab.mentions.parameters(filter: nil, until: "cursor", oldestFirst: true, date: date), ["limit": .number(10), "sinceId": .string("cursor")])
    }

    func testGroupedCursorCanAdvanceEvenAfterOneVisibleGroup() {
        let page = [Record(.object(["id": .string("oldest-id"), "type": .string("reaction:grouped")]))]
        XCTAssertEqual(NotificationKind(record: page[0]), .reaction)
        XCTAssertEqual(NotificationKind.allCases.count, 20)
        XCTAssertTrue(NotificationTab.all.canLoadOlder(page, previousCursor: "newer"))
        XCTAssertFalse(NotificationTab.all.canLoadOlder(page, previousCursor: "oldest-id"))
        XCTAssertFalse(NotificationTab.all.canLoadOlder([], previousCursor: "newer"))
        XCTAssertFalse(NotificationTab.mentions.canLoadOlder(page, previousCursor: nil))
    }

    func testBadgeSourceCountFallbackAndExplicitRead() {
        var badges = NotificationBadges()
        for (value, label) in [(12, "12"), (99, "99"), (126, "99+")] {
            badges.applyAccount(.object(["hasUnreadNotification": .bool(true), "unreadNotificationsCount": .number(Double(value))]))
            XCTAssertEqual(badges.notificationLabel, label)
        }
        badges.applyAccount(.null)
        XCTAssertEqual(badges.notificationLabel, "99+")
        badges.applyAccount(.object(["hasUnreadNotification": .bool(true)]))
        XCTAssertEqual(badges.notificationLabel, "•")
        badges.applyAccount(.object(["hasUnreadNotification": .bool(false), "unreadNotificationsCount": .number(7)]))
        XCTAssertNil(badges.notificationLabel)
        badges.applyAccount(.object(["hasUnreadNotification": .bool(true), "unreadNotificationsCount": .number(2.5)]))
        XCTAssertEqual(badges.notificationLabel, "•")
        badges.markNotificationsRead()
        XCTAssertNil(badges.notificationLabel)
    }

    func testGroupedTargetAndUnavailableNoteNeverOpenUnrelatedProfile() {
        let user: JSONValue = .object(["id": .string("actor")])
        let note: JSONValue = .object(["id": .string("source")])
        for type in ["reaction:grouped", "renote:grouped", "mention", "quote", "reply", "note", "reaction", "pollEnded"] {
            XCTAssertEqual(NotificationTarget.resolve(Record(.object(["type": .string(type), "user": user, "note": note]))), .note("source"))
            XCTAssertEqual(NotificationTarget.resolve(Record(.object(["type": .string(type), "user": user]))), .none)
        }
        for type in ["app", "test", "unknown"] {
            XCTAssertEqual(NotificationTarget.resolve(Record(.object(["type": .string(type), "user": user, "note": note]))), .none)
        }
    }
}
