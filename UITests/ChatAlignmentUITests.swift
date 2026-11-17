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
    private func assertPrivateMetadataLayout(_ app: XCUIApplication, theme: String) {
        for id in ["private0001", "private0002"] {
            let menu = app.buttons["chat.menu." + id]
            // Measure the existing selectable text element. An ancestor identifier
            // would replace chat.text.* and break recovery/accessibility clients.
            let text = app.descendants(matching: .any).matching(identifier: "chat.text." + id).firstMatch
            let metadata = app.descendants(matching: .any).matching(identifier: "chat.metadata." + id).firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 6))
            XCTAssertTrue(text.waitForExistence(timeout: 6))
            XCTAssertTrue(metadata.waitForExistence(timeout: 6))
            // The existing message entrance animation may still be running
            // when AX first exposes the elements. Wait for the same strict
            // geometry, never for a weaker substitute or a coordinate fallback.
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let target = menu.frame, body = text.frame, details = metadata.frame
                guard puboTouchRectMeetsMinimum(target), menu.isHittable,
                      body.width > 0, body.height > 0, details.width > 0, details.height > 0,
                      body.minX.isFinite, body.minY.isFinite, body.maxX.isFinite, body.maxY.isFinite,
                      details.minX.isFinite, details.minY.isFinite, details.maxX.isFinite, details.maxY.isFinite,
                      !target.intersects(body), !target.intersects(details), details.height < 44,
                      details.minY >= max(target.maxY, body.maxY),
                      details.minY - max(target.maxY, body.maxY) <= 7 else { return false }
                return true
            }, object: nil)
            let result = XCTWaiter.wait(for: [settled], timeout: 8)
            let target = menu.frame, body = text.frame, details = metadata.frame
            XCTAssertTrue(puboTouchRectMeetsMinimum(target), "Menu keeps its real 44pt touch target")
            XCTAssertTrue(menu.isHittable)
            XCTAssertFalse(target.intersects(body), "Menu must not cover selectable message content")
            XCTAssertFalse(target.intersects(details), "Menu must not cover metadata")
            XCTAssertLessThan(details.height, 44, "Ordinary fixture metadata must not inherit menu height")
            XCTAssertGreaterThanOrEqual(details.minY, max(target.maxY, body.maxY))
            XCTAssertLessThanOrEqual(details.minY - max(target.maxY, body.maxY), 7)
            let geometry = XCTAttachment(string: "theme=\(theme)\nid=\(id)\nmenu=\(target)\ntext=\(body)\nmetadata=\(details)\n")
            geometry.name = "chat-private-metadata-" + theme + "-" + id
            geometry.lifetime = .keepAlways; add(geometry)
            XCTAssertEqual(result, .completed, "Private metadata geometry must settle without relaxing targets")
        }
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
            assertPrivateMetadataLayout(app, theme: theme)
            XCTAssertTrue(app.buttons["取消反应 ❤"].exists); capture(app, "chat-private-" + theme)
            for id in ["private0001", "private0002"] {
                let menu = app.buttons["chat.menu." + id]
                XCTAssertTrue(menu.isHittable); menu.tap()
                let details = app.buttons["chat.actions." + id]
                XCTAssertTrue(details.waitForExistence(timeout: 6)); details.tap()
                let sheet = app.navigationBars["消息操作"]
                XCTAssertTrue(sheet.waitForExistence(timeout: 6))
                let close = sheet.buttons["关闭"]
                XCTAssertTrue(close.waitForExistence(timeout: 6)); close.tap()
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 6))
            }
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
            bubble.press(forDuration: 1)
            let reportAction = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)", "举报", XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue)).firstMatch
            XCTAssertTrue(reportAction.waitForExistence(timeout: 5)); capture(app, "chat-room-menu-" + theme); reportAction.tap()
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
    func testTextSelectionMenuPreservesRoomActionsBothThemes() {
        for dark in [false, true] {
            let app = launch(dark ? ["--dark"] : []); room(app)
            let own = app.descendants(matching: .any).matching(identifier: "room.bubble.room0002").firstMatch
            XCTAssertTrue(own.waitForExistence(timeout: 6))
            let ownText = own.textViews.firstMatch
            XCTAssertTrue(ownText.exists); ownText.press(forDuration: 1)
            let delete = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)", "删除消息", XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue)).firstMatch
            XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
            XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 5))
            capture(app, "chat-text-menu-delete-confirm-" + (dark ? "dark" : "light"))
            app.buttons["取消"].tap(); XCTAssertTrue(own.exists, "Cancel must retain the original message")
            ownText.press(forDuration: 1)
            XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
            let confirmDelete = app.buttons["删除消息"]
            XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5)); confirmDelete.tap()
            XCTAssertTrue(own.waitForNonExistence(timeout: 6), "Confirmed deletion must remove the original message")
            capture(app, "chat-text-menu-deleted-" + (dark ? "dark" : "light"))
            let foreign = app.descendants(matching: .any).matching(identifier: "room.bubble.room0001").firstMatch
            XCTAssertTrue(foreign.textViews.firstMatch.exists); foreign.textViews.firstMatch.press(forDuration: 1)
            let report = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)", "举报", XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue)).firstMatch
            XCTAssertTrue(report.waitForExistence(timeout: 5)); report.tap()
            let reason = app.textViews["report.reason"]
            XCTAssertTrue(reason.waitForExistence(timeout: 5))
            XCTAssertTrue((reason.value as? String)?.contains("/chat/messages/room0001") == true)
            XCTAssertFalse((reason.value as? String)?.contains("欢迎来到音乐交流群") == true)
            capture(app, "chat-text-menu-report-" + (dark ? "dark" : "light"))
            app.buttons["取消"].tap(); app.terminate()
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
        let input = app.textViews["room.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 6))
        input.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            capture(app, "chat-room-input-keyboard-missing")
            XCTFail("Input precondition failed: keyboard did not appear before typing")
            return
        }
        input.typeText("保留输入内容")
        let completeInput = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "保留输入内容"), object: input)
        guard XCTWaiter.wait(for: [completeInput], timeout: 5) == .completed else {
            capture(app, "chat-room-input-incomplete-before-tabs")
            XCTFail("Input precondition failed before tab switch; draft restoration was not exercised")
            return
        }
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
