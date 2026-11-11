import XCTest

final class SocialAlignmentUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--social-align"] + flags; app.launch()
        XCTAssertTrue(app.tabBars.buttons["动态"].waitForExistence(timeout: 12)); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable)
    }
    private func openPrivate(_ app: XCUIApplication) {
        app.tabBars.buttons["私信"].tap(); let peer = app.staticTexts["测试朋友"].firstMatch; XCTAssertTrue(peer.waitForExistence(timeout: 6)); peer.tap()
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 6))
    }
    private func openRoom(_ app: XCUIApplication) {
        app.tabBars.buttons["通知"].tap(); let row = app.buttons["notification.socialnotice1"]; XCTAssertTrue(row.waitForExistence(timeout: 6)); row.tap()
        XCTAssertTrue(app.navigationBars["PUBO 音乐交流"].waitForExistence(timeout: 6)); XCTAssertTrue(app.textViews["room.input"].exists)
    }
    func testContextCardsNavigateToExactOriginalInBothThemes() {
        for dark in [false, true] {
            let app = launch(dark ? ["--dark"] : [])
            let context = app.buttons["note.context.socialorigin"].firstMatch; reveal(app, context)
            capture(app, "social-context-" + (dark ? "dark" : "light")); context.tap()
            XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["周末一起听歌吧，记得带上耳机。"].waitForExistence(timeout: 5))
            capture(app, "social-original-" + (dark ? "dark" : "light")); app.terminate()
        }
    }
    func testNotificationDestinationsAndSpecifiedNotes() {
        let app = launch(); app.tabBars.buttons["通知"].tap()
        let achievement = app.buttons["notification.socialnotice2"]; XCTAssertTrue(achievement.waitForExistence(timeout: 6)); capture(app, "social-notifications-light"); achievement.tap()
        XCTAssertTrue(app.navigationBars["成就"].waitForExistence(timeout: 5)); app.navigationBars.buttons.firstMatch.tap()
        app.buttons["notification.socialnotice3"].tap()
        XCTAssertTrue(app.navigationBars["导出文件"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["查看与保存导出文件"].waitForExistence(timeout: 5)); capture(app, "social-export-destination")
        app.navigationBars.buttons.firstMatch.tap()
        app.descendants(matching: .any).matching(identifier: "notifications.tab.directNotes").firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "note.open.socialdirect").firstMatch.waitForExistence(timeout: 5)); capture(app, "social-specified-notes")
    }
    func testRoomBubblesReactionEmojiAndFileMenuInBothThemes() {
        for dark in [false, true] {
            let app = launch(dark ? ["--dark"] : []); openRoom(app)
            let own = app.descendants(matching: .any).matching(identifier: "room.bubble.room0002").firstMatch
            let peer = app.descendants(matching: .any).matching(identifier: "room.bubble.room0001").firstMatch
            XCTAssertTrue(own.waitForExistence(timeout: 5)); XCTAssertGreaterThan(own.frame.maxX, peer.frame.maxX)
            capture(app, "social-room-" + (dark ? "dark" : "light"))
            let remove = app.buttons["取消反应 ❤"]; XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap(); XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
            app.buttons["插入群聊表情"].tap(); app.buttons["👍"].tap()
            XCTAssertTrue((app.textViews["room.input"].value as? String)?.contains("👍") == true)
            app.buttons["room.send"].tap(); XCTAssertTrue(app.staticTexts["👍"].waitForExistence(timeout: 5))
            app.buttons["添加群聊附件"].tap(); XCTAssertTrue(app.buttons["选择本地文件"].exists); XCTAssertTrue(app.buttons["选择图片或视频"].exists); app.buttons["从网盘选择"].tap()
            XCTAssertTrue(app.navigationBars["我的网盘"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["取消"].exists); capture(app, "social-room-drive-picker-" + (dark ? "dark" : "light")); app.buttons["取消"].tap()
            app.buttons["room.tab.about"].tap(); XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "room.about").firstMatch.waitForExistence(timeout: 5)); app.buttons["room.tab.messages"].tap(); app.terminate()
        }
    }
    func testPrivateSettingsAndReactionInBothThemes() {
        for dark in [false, true] {
            let app = launch(dark ? ["--dark"] : []); openPrivate(app)
            XCTAssertTrue(app.buttons["录制语音"].exists); capture(app, "social-private-" + (dark ? "dark" : "light"))
            app.buttons["聊天选项"].tap(); app.buttons["开启免打扰"].tap()
            app.buttons["聊天选项"].tap(); XCTAssertTrue(app.buttons["关闭免打扰"].waitForExistence(timeout: 5)); app.buttons["置顶会话"].tap()
            app.buttons["聊天选项"].tap(); XCTAssertTrue(app.buttons["取消置顶"].waitForExistence(timeout: 5)); capture(app, "social-private-settings-" + (dark ? "dark" : "light")); app.buttons["关闭免打扰"].tap()
            let remove = app.buttons["取消反应 ❤"]; XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap(); XCTAssertTrue(remove.waitForNonExistence(timeout: 5)); app.terminate()
        }
    }
    func testPostLimitRetainsDraftAndDisablesSend() {
        let app = launch(); app.buttons["home.compose"].tap()
        let editor = app.textViews["compose.text"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText(String(repeating: "a", count: 61))
        XCTAssertEqual((editor.value as? String)?.count, 61, "连续键盘输入不能丢字或失焦")
        XCTAssertTrue(app.staticTexts["compose.limit"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["compose.send"].isEnabled)
        capture(app, "social-post-limit")
        editor.typeText(XCUIKeyboardKey.delete.rawValue)
        // SwiftUI can temporarily rebuild the accessibility node after the limit
        // banner disappears. Re-query it instead of holding the previous snapshot.
        let updatedText = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = app.textViews.matching(identifier: "compose.text").firstMatch
            return current.exists && current.value as? String == String(repeating: "a", count: 60)
        }, object: nil)
        let textResult = XCTWaiter.wait(for: [updatedText], timeout: 10)
        if textResult != .completed {
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "post-limit-recovery-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
            capture(app, "social-post-limit-recovery-failed")
        }
        XCTAssertEqual(textResult, .completed)
        let enabledSend = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["compose.send"])
        XCTAssertEqual(XCTWaiter.wait(for: [enabledSend], timeout: 10), .completed)
        capture(app, "social-post-limit-recovered")
    }
    func testUncertainRoomSendKeepsDraftAndPreventsDuplicate() {
        let app = launch(["--lost-room-response"]); openRoom(app)
        let input = app.textViews["room.input"]; input.tap(); input.typeText("保留这条待核对消息")
        app.buttons["room.send"].tap()
        XCTAssertTrue(app.staticTexts["发送结果待核对。请检查本群最新消息；不会自动重发。"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["room.send"].isEnabled); XCTAssertEqual(input.value as? String, "保留这条待核对消息"); capture(app, "social-room-uncertain")
    }
}
