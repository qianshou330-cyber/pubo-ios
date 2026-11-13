import XCTest

final class ChatAlignmentUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--social-align", "--chat-align"] + flags; app.launch()
        XCTAssertTrue(puboTab(app, "消息").waitForExistence(timeout: 15)); puboSelectTab(app, "消息")
        XCTAssertTrue(app.buttons["messages.add"].waitForExistence(timeout: 8)); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func assertRoomInsets(_ app: XCUIApplication, firstRowAtTop: Bool, stage: String) {
        let viewport = app.scrollViews["room.timeline"]
        let avatar = app.buttons["room.avatar.room0001"]
        let composer = app.descendants(matching: .any).matching(identifier: "room.composer").firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 6))
        XCTAssertTrue(avatar.waitForExistence(timeout: 6))
        XCTAssertTrue(composer.waitForExistence(timeout: 6))
        // This fixed three-message fixture fits even the small ordinary-text
        // viewport. Do not infer content insets from an offscreen lazy row.
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let row = avatar.frame, visible = viewport.frame
            guard puboTouchRectMeetsMinimum(row),
                  abs(row.minX - visible.minX - 16) <= 1,
                  row.minY >= visible.minY,
                  row.maxY <= min(visible.maxY, composer.frame.minY) else { return false }
            return !firstRowAtTop || abs(row.minY - visible.minY - 16) <= 1
        }, object: nil)
        let result = XCTWaiter.wait(for: [settled], timeout: 8)
        let geometry = XCTAttachment(string: "stage=\(stage)\nviewport=\(viewport.frame)\navatar=\(avatar.frame)\ncomposer=\(composer.frame)\n" + app.debugDescription)
        geometry.name = "chat-room-insets-" + stage; geometry.lifetime = .keepAlways; add(geometry)
        XCTAssertEqual(result, .completed, "Group insets must remain stable during " + stage)
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
            puboSelectTab(app, "好友"); puboTapVisible(app, "friends.rooms")
            XCTAssertTrue(app.navigationBars["群聊"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["创建群聊"].exists)
            for (tab, expected) in [("邀请", "新朋友邀请"), ("已加入", "PUBO 音乐交流"), ("我创建的", "我的音乐小组")] {
                let button = app.segmentedControls.buttons[tab]
                XCTAssertTrue(button.waitForExistence(timeout: 6)); button.tap()
                XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 6)); capture(app, "chat-" + tab + "-" + theme)
                XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "app.tab.")).count, 4)
            }
            app.terminate()
        }
    }
    func testPrivateSearchDateAndReactionsBothThemes() {
        for dark in [false, true] {
            let theme = dark ? "dark" : "light", app = launch(dark ? ["--dark"] : []); peer(app)
            XCTAssertTrue(app.staticTexts["日期 11/3 · 11/2"].waitForExistence(timeout: 6))
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
            XCTAssertTrue(app.staticTexts["日期 11/3 · 11/4"].waitForExistence(timeout: 6))
            assertRoomInsets(app, firstRowAtTop: true, stage: "initial-" + theme)
            capture(app, "chat-room-" + theme)
            app.buttons["room.tab.search"].tap(); let input = app.textFields["chat.search.query"]; XCTAssertTrue(input.waitForExistence(timeout: 6)); input.tap(); input.typeText("欢迎")
            let found = app.staticTexts["欢迎来到音乐交流群。"]; XCTAssertTrue(found.waitForExistence(timeout: 6)); capture(app, "chat-room-search-" + theme); found.tap()
            XCTAssertTrue(app.buttons["回到最新消息"].waitForExistence(timeout: 6))
            let bubble = app.descendants(matching: .any).matching(identifier: "room.bubble.room0001").firstMatch; XCTAssertTrue(bubble.waitForExistence(timeout: 6))
            assertRoomInsets(app, firstRowAtTop: false, stage: "context-" + theme)
            capture(app, "chat-room-context-" + theme)
            bubble.press(forDuration: 1); XCTAssertTrue(app.buttons["举报"].waitForExistence(timeout: 5)); capture(app, "chat-room-menu-" + theme); app.buttons["举报"].tap()
            let reason = app.textViews["report.reason"]; XCTAssertTrue(reason.waitForExistence(timeout: 5)); XCTAssertTrue((reason.value as? String)?.contains("/chat/messages/room0001") == true)
            XCTAssertFalse((reason.value as? String)?.contains("欢迎来到音乐交流群") == true); capture(app, "chat-room-report-" + theme); app.buttons["取消"].tap()
            app.buttons["回到最新消息"].tap()
            XCTAssertTrue(app.buttons["回到最新消息"].waitForNonExistence(timeout: 6))
            assertRoomInsets(app, firstRowAtTop: true, stage: "latest-" + theme)
            capture(app, "chat-room-latest-" + theme)
            app.buttons["room.tab.members"].tap(); XCTAssertTrue(app.staticTexts["测试用户"].waitForExistence(timeout: 5)); capture(app, "chat-room-members-" + theme)
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
        let menu = app.buttons["room.menu.room0003"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        menu.tap()
        let report = app.buttons["举报"]
        let presented = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: report)
        XCTAssertEqual(XCTWaiter.wait(for: [presented], timeout: 8), .completed)
        report.tap()
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
        let body = app.staticTexts["room.bubble.room0003"]
        XCTAssertTrue(body.waitForExistence(timeout: 6))
        XCTAssertEqual(body.value as? String, "今天一起分享喜欢的舞台。")
        let renderedBody = body.textViews.firstMatch
        XCTAssertEqual(body.textViews.count, 1)
        XCTAssertTrue(renderedBody.exists)
        XCTAssertEqual(renderedBody.label, "今天一起分享喜欢的舞台。")
        // C17's ordinary-size AX tree measured this text at 15.5pt high. Its
        // large-text screenshot also looked unscaled, but had no exported AX tree.
        // This new check measures actual TextKit geometry, not bubble padding.
        XCTAssertGreaterThan(renderedBody.frame.height, 22, "Large-text mode must enlarge the message body too")
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
