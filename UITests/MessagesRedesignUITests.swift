import XCTest

/// Optional real-interaction proof. The required jobs keep their existing selectors.
final class MessagesRedesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private let peerID = "user:syntheticpeer"
    private let roomID = "room:socialroom"
    private let nickname = "这是用于检验消息列表末尾截断而故意设置的很长很长的合成昵称"
    private let longPreview = "这是一段用于观察消息列表单行摘要省略行为的很长测试文本，不包含真实用户数据。"

    private func launch(dark: Bool = false, layout: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--social-align", "--chat-align", "--reduce-motion"]
            + (layout ? ["--messages-redesign-fixture"] : []) + (dark ? ["--dark"] : [])
        app.launch()
        ready(app.buttons["messages.search.open"], "Messages home")
        return app
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func ready(_ control: XCUIElement, _ reason: String, timeout: TimeInterval = 8) {
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in control.exists && control.isHittable }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: timeout), .completed, reason)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "messages-redesign-" + name; shot.lifetime = .keepAlways; add(shot)
    }
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        ready(button, "Real navigation Back"); button.tap()
    }
    private func openSearch(_ app: XCUIApplication) -> XCUIElement {
        let entry = app.buttons["messages.search.open"]
        XCTAssertFalse(app.textFields["chat.search.query"].exists, "Search field belongs to a separate route")
        ready(entry, "Global search route"); entry.tap()
        let input = app.textFields["chat.search.query"]
        ready(input, "Global search input")
        XCTAssertTrue(element(app, "messages.search.readOnlyNotice").exists)
        return input
    }
    private func assertUnread(_ app: XCUIApplication, privateCount: String, roomUnread: Bool) {
        let count = element(app, "messages.unread." + peerID)
        let badge = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in count.exists && count.label == privateCount }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [badge], timeout: 8), .completed, "Private count")
        let room = element(app, "messages.unread." + roomID)
        if roomUnread {
            XCTAssertTrue(room.waitForExistence(timeout: 8), "Room retains its dot")
            XCTAssertEqual(room.label, "有未读消息")
        } else {
            XCTAssertTrue(app.buttons["conversation." + roomID].exists, "Only the dot should disappear")
            XCTAssertTrue(room.waitForNonExistence(timeout: 8), "Ordinary room timeline read clears its dot")
        }
    }

    func testGlobalSearchPreviewsPrivateAndRoomWithoutMarkingRead() {
        let app = launch(layout: true); defer { app.terminate() }
        assertUnread(app, privateCount: "99+", roomUnread: true)
        let input = openSearch(app); input.tap(); input.typeText("欢迎")
        for (id, body) in [("private0001", "你好，欢迎来到 PUBO。"), ("room0001", "欢迎来到音乐交流群。")] {
            let result = app.buttons["messages.search.result." + id]
            ready(result, "Global result " + id); result.tap()
            let preview = element(app, "messages.search.result.preview")
            XCTAssertTrue(preview.waitForExistence(timeout: 8))
            XCTAssertEqual(preview.label, body)
            XCTAssertFalse(app.textViews["chat.input"].exists)
            XCTAssertFalse(app.textViews["room.input"].exists)
            capture(app, "search-preview-" + id)
            back(app)
            ready(input, "Search is restored after closing the read-only preview")
        }
        back(app)
        ready(app.buttons["messages.search.open"], "Messages after closing global Search")
        assertUnread(app, privateCount: "99+", roomUnread: true)
        capture(app, "unread-after-two-read-only-previews")

        // Positive controls in the same invocation: ordinary chats really do
        // call the read-capable paths. The Debug transport returns the new
        // server-side fixture state, not a hard-coded always-unread label.
        let direct = app.buttons["conversation." + peerID]
        ready(direct, "Ordinary private row"); direct.tap()
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 8))
        XCTAssertTrue(element(app, "chat.text.private0001").waitForExistence(timeout: 8))
        back(app)
        ready(app.buttons["messages.search.open"], "Messages after ordinary private")
        assertUnread(app, privateCount: "99", roomUnread: true)
        let room = app.buttons["conversation." + roomID]
        ready(room, "Ordinary room row"); room.tap()
        XCTAssertTrue(app.textViews["room.input"].waitForExistence(timeout: 8))
        XCTAssertTrue(element(app, "room.bubble.room0003").waitForExistence(timeout: 8))
        back(app)
        ready(app.buttons["messages.search.open"], "Messages after ordinary room")
        assertUnread(app, privateCount: "99", roomUnread: false)
        capture(app, "ordinary-chats-read-positive-control")
    }

    func testPlusKeepsBothFriendSheetsAndRealClose() {
        let app = launch(); defer { app.terminate() }
        XCTAssertEqual(app.staticTexts["messages.title"].label, "消息", "Messages title")
        for (itemID, closeID, proofID) in [
            ("messages.scan", "scanner.close", "演示测试不启用相机，请使用用户名搜索。"),
            ("messages.addUsername", "addFriend.close", "addFriend.username"),
        ] {
            let plus = app.buttons["messages.add"]
            ready(plus, "Plus menu"); plus.tap()
            let scan = app.buttons["messages.scan"], username = app.buttons["messages.addUsername"]
            ready(scan, "Scan entry"); ready(username, "Username entry")
            XCTAssertFalse(app.buttons["创建群聊"].exists)
            XCTAssertFalse(app.buttons["建群"].exists)
            capture(app, "plus-" + itemID)
            app.buttons[itemID].tap()
            XCTAssertTrue(element(app, proofID).waitForExistence(timeout: 8))
            XCTAssertFalse(app.alerts.firstMatch.exists, "Synthetic sheets must not request real permissions")
            let close = app.buttons[closeID]
            ready(close, closeID); capture(app, "sheet-" + itemID); close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 8))
            ready(app.buttons["messages.search.open"], "Messages after sheet dismissal")
            XCTAssertEqual(app.staticTexts["messages.title"].label, "消息")
        }
    }

    func testDenseListLongNameBadgesAndLastRowBothThemes() {
        for dark in [false, true] {
            let theme = dark ? "dark" : "light", app = launch(dark: dark, layout: true)
            defer { app.terminate() }
            let direct = app.buttons["conversation." + peerID]
            ready(direct, "Long-name private row")
            XCTAssertTrue(direct.label.contains(nickname), "Combined accessibility label keeps full name")
            XCTAssertTrue(direct.label.contains(longPreview), "Combined accessibility label keeps full preview")
            XCTAssertEqual(direct.value as? String, "@friend")
            assertUnread(app, privateCount: "99+", roomUnread: true)
            capture(app, "long-name-preview-unread-" + theme)
            let name = element(app, "messages.name." + peerID), preview = element(app, "messages.preview." + peerID)
            let time = element(app, "messages.time." + peerID), badge = element(app, "messages.unread." + peerID)
            for leaf in [name, preview, time, badge] {
                XCTAssertTrue(leaf.exists)
                XCTAssertGreaterThan(leaf.frame.width, 0)
                XCTAssertGreaterThan(leaf.frame.height, 0)
                XCTAssertTrue(direct.frame.insetBy(dx: -1, dy: -1).contains(leaf.frame))
            }
            XCTAssertLessThanOrEqual(name.frame.maxX, time.frame.minX + 1, "Long name cannot cover the time")
            XCTAssertLessThanOrEqual(preview.frame.maxX, badge.frame.minX + 1, "Long preview cannot cover the badge")

            let window = app.windows.firstMatch, bar = element(app, "app.tabBar")
            XCTAssertTrue(bar.exists)
            let last = app.buttons["conversation.user:layoutpeer12"]
            XCTAssertFalse(last.isHittable, "Dense fixture must require actual scroll")
            // Keep each real drag out of the pinned bottom-bar area, never inject list offsets.
            for _ in 0..<6 where !last.isHittable || last.frame.maxY > bar.frame.minY + 1 {
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.77))
                    .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)))
            }
            let clear = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard last.exists, last.isHittable else { return false }
                let rect = last.frame, tab = bar.frame, screen = window.frame
                return rect.height >= 44 && tab.height > 0 && screen.height > 0
                    && rect.minY >= screen.minY && rect.maxY <= tab.minY + 1
            }, object: nil)
            let result = XCTWaiter.wait(for: [clear], timeout: 8)
            let geometry = XCTAttachment(string: "last=\(last.frame); bar=\(bar.frame); window=\(window.frame)")
            geometry.name = "messages-redesign-last-row-geometry-" + theme; geometry.lifetime = .keepAlways; add(geometry)
            capture(app, "last-row-clear-of-tab-bar-" + theme)
            XCTAssertEqual(result, .completed, "Whole final row is readable and hittable above the tab bar")
        }
    }

    func testPrivateRowTrailingTouchOpensChatAndLongPressPreservesMenu() {
        let app = launch(layout: true); defer { app.terminate() }
        let direct = app.buttons["conversation." + peerID]
        ready(direct, "Private row")
        // Deliberately touch the far trailing interior, away from name/avatar.
        let trailing = direct.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.50))
        trailing.tap()
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 8))
        back(app)
        ready(direct, "Private row after native Back")
        trailing.press(forDuration: 1)
        for title in ["置顶", "免打扰"] {
            let action = app.descendants(matching: .any).matching(NSPredicate(
                format: "label == %@ AND (elementType == %d OR elementType == %d)",
                title, XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue
            )).firstMatch
            ready(action, "Original private conversation action " + title)
        }
        XCTAssertFalse(app.textViews["chat.input"].exists, "Long press is not a normal navigation tap")
        capture(app, "private-long-press-native-menu")
    }
}
