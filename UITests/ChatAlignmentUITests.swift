import XCTest

final class ChatAlignmentUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--social-align", "--chat-align"] + flags; app.launch()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 15)); app.tabBars.buttons["私信"].tap()
        XCTAssertTrue(app.buttons["chat.home.home"].waitForExistence(timeout: 8)); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func room(_ app: XCUIApplication) {
        let row = app.buttons["conversation.room:socialroom"]
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        XCTAssertTrue(app.textViews["room.input"].waitForExistence(timeout: 8))
    }
    private func peer(_ app: XCUIApplication) {
        let row = app.buttons["conversation.user:syntheticpeer"]
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 8))
    }
    func testMixedConversationsAndHomeTabsBothThemes() {
        for dark in [false, true] {
            let theme = dark ? "dark" : "light", app = launch(dark ? ["--dark"] : [])
            XCTAssertTrue(app.staticTexts["99+"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["conversation.room:socialroom"].exists); XCTAssertTrue(app.buttons["conversation.user:syntheticpeer"].exists)
            capture(app, "chat-home-" + theme)
            for (tab, expected) in [("invited", "新朋友邀请"), ("joining", "PUBO 音乐交流"), ("owned", "我的音乐小组")] {
                let button = app.buttons["chat.home." + tab]; if !button.isHittable { app.scrollViews.firstMatch.swipeLeft() }; button.tap()
                XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 6)); capture(app, "chat-" + tab + "-" + theme)
                XCTAssertEqual(app.tabBars.buttons.count, 4)
            }
            app.terminate()
        }
    }
    func testPrivateSearchDateAndReactionsBothThemes() {
        for dark in [false, true] {
            let theme = dark ? "dark" : "light", app = launch(dark ? ["--dark"] : []); peer(app)
            XCTAssertTrue(app.staticTexts["日期 11/2 · 11/3"].waitForExistence(timeout: 6))
            XCTAssertTrue(app.buttons["取消反应 ❤"].exists); capture(app, "chat-private-" + theme)
            app.buttons["添加反应 ❤"].tap(); XCTAssertTrue(app.buttons["取消反应 ❤"].exists, "Clicking another participant must not remove my reaction")
            app.buttons["取消反应 ❤"].tap(); XCTAssertTrue(app.buttons["取消反应 ❤"].waitForNonExistence(timeout: 6))
            app.buttons["chat.tab.search"].tap()
            let input = app.textFields["chat.search.query"]; XCTAssertTrue(input.waitForExistence(timeout: 6)); input.tap(); input.typeText("欢迎")
            XCTAssertTrue(app.staticTexts["你好，欢迎来到 PUBO。"].waitForExistence(timeout: 6)); capture(app, "chat-private-search-" + theme)
            app.buttons["chat.tab.messages"].tap(); XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 6)); app.terminate()
        }
    }
    func testGroupSearchExactMessageReportAndMenuBothThemes() {
        for dark in [false, true] {
            let theme = dark ? "dark" : "light", app = launch(dark ? ["--dark"] : []); room(app)
            XCTAssertTrue(app.staticTexts["日期 11/3 · 11/4"].waitForExistence(timeout: 6)); capture(app, "chat-room-" + theme)
            app.buttons["room.tab.search"].tap(); let input = app.textFields["chat.search.query"]; XCTAssertTrue(input.waitForExistence(timeout: 6)); input.tap(); input.typeText("欢迎")
            let found = app.staticTexts["欢迎来到音乐交流群。"]; XCTAssertTrue(found.waitForExistence(timeout: 6)); capture(app, "chat-room-search-" + theme); found.tap()
            XCTAssertTrue(app.buttons["回到最新消息"].waitForExistence(timeout: 6))
            let bubble = app.descendants(matching: .any).matching(identifier: "room.bubble.room0001").firstMatch; XCTAssertTrue(bubble.waitForExistence(timeout: 6)); capture(app, "chat-room-context-" + theme)
            bubble.press(forDuration: 1); XCTAssertTrue(app.buttons["举报"].waitForExistence(timeout: 5)); capture(app, "chat-room-menu-" + theme); app.buttons["举报"].tap()
            let reason = app.textViews["report.reason"]; XCTAssertTrue(reason.waitForExistence(timeout: 5)); XCTAssertTrue((reason.value as? String)?.contains("/chat/messages/room0001") == true)
            XCTAssertFalse((reason.value as? String)?.contains("欢迎来到音乐交流群") == true); capture(app, "chat-room-report-" + theme); app.buttons["取消"].tap()
            app.buttons["回到最新消息"].tap(); app.buttons["room.tab.members"].tap(); XCTAssertTrue(app.staticTexts["测试用户"].waitForExistence(timeout: 5)); capture(app, "chat-room-members-" + theme)
            app.buttons["room.tab.about"].tap(); XCTAssertTrue(app.staticTexts["一起分享音乐和日常。"].waitForExistence(timeout: 5)); capture(app, "chat-room-about-" + theme)
            app.terminate()
        }
    }
    func testGroupReactionDoesNotUseDirectMessagePermission() {
        let app = launch(); room(app)
        let remove = app.buttons["取消反应 ❤"]; for _ in 0..<5 where !remove.isHittable { app.swipeDown() }
        XCTAssertTrue(remove.waitForExistence(timeout: 6)); remove.tap(); XCTAssertTrue(remove.waitForNonExistence(timeout: 6))
        app.buttons["添加反应 ❤"].tap(); XCTAssertTrue(remove.waitForExistence(timeout: 6)); capture(app, "chat-room-reaction-readback")
    }
    func testReportUnknownOutcomeDisablesResubmission() {
        let app = launch(["--report-uncertain"]); room(app)
        app.buttons["room.menu.room0003"].tap(); app.buttons["举报"].tap()
        let reason = app.textViews["report.reason"]; XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["提交"].isEnabled); reason.tap(); reason.typeText("隔离举报原因"); app.buttons["提交"].tap()
        XCTAssertTrue(app.staticTexts["提交结果尚未确认，请稍后核对；此页不会重复提交。"].waitForExistence(timeout: 8)); XCTAssertFalse(app.buttons["提交"].isEnabled); capture(app, "chat-report-uncertain")
    }
    func testGroupDraftSurvivesTabsAndKeyboard() {
        let app = launch(); room(app)
        let input = app.textViews["room.input"]; input.tap(); input.typeText("保留输入内容")
        capture(app, "chat-room-keyboard"); app.buttons["room.tab.search"].tap(); app.buttons["room.tab.messages"].tap()
        XCTAssertEqual(app.textViews["room.input"].value as? String, "保留输入内容"); capture(app, "chat-room-draft-restored")
    }
    func testStaleOtherParticipantReactionCannotCancelExistingMine() {
        let app = launch(["--stale-room-reaction"]); room(app)
        let add = app.buttons["添加反应 ❤"]; for _ in 0..<4 where !add.isHittable { app.swipeDown() }
        XCTAssertTrue(add.waitForExistence(timeout: 6)); XCTAssertFalse(app.buttons["取消反应 ❤"].exists)
        add.tap(); XCTAssertTrue(app.buttons["取消反应 ❤"].waitForExistence(timeout: 6)); capture(app, "chat-room-stale-add-safe")
    }
    func testLargeTextGroupComposerAndTabsStayReachable() {
        let app = launch(["--large-text", "--dark"]); room(app)
        let input = app.textViews["room.input"]; XCTAssertTrue(input.isHittable); input.tap(); input.typeText("大字体草稿")
        XCTAssertTrue(app.buttons["room.send"].isHittable); capture(app, "chat-room-large-keyboard")
        let search = app.buttons["room.tab.search"]; if !search.isHittable { app.scrollViews.firstMatch.swipeLeft() }; search.tap()
        XCTAssertTrue(app.textFields["chat.search.query"].waitForExistence(timeout: 6)); capture(app, "chat-room-large-search")
    }
    func testAnimatedReactionKeepsRatioAndPlaysAtLargeTextSize() {
        let app = launch(["--chat-animated-reaction", "--gif-preview", "--large-text", "--dark"]); room(app)
        let image = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND value CONTAINS %@", "timeline.animatedImage", "frame=")).firstMatch
        for _ in 0..<5 where !image.isHittable { app.swipeDown() }
        XCTAssertTrue(image.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(image.frame.height, 24.1)
        XCTAssertEqual(image.frame.width / image.frame.height, 320.0 / 180.0, accuracy: 0.05)
        let initial = image.value as? String ?? ""
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && (image.value as? String ?? "") == initial { Thread.sleep(forTimeInterval: 0.07) }
        XCTAssertNotEqual(image.value as? String ?? "", initial)
        XCTAssertTrue((image.value as? String)?.contains("playing=true") == true)
        capture(app, "chat-room-animated-reaction-large")
    }
}
