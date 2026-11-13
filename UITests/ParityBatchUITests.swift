import XCTest

final class ParityBatchUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--timeline-align"] + flags; app.launch()
        XCTAssertTrue(puboTab(app, "世界圈").waitForExistence(timeout: 15)); puboSelectTab(app, "世界圈"); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testReplyKeepsFollowersVisibilityBothThemes() {
        for dark in [false, true] {
            let app = launch(["--private-reply-preview"] + (dark ? ["--dark"] : []))
            let reply = app.buttons["note.reply.at4tltest0025"].firstMatch
            for _ in 0..<5 where !reply.isHittable { app.swipeUp() }
            XCTAssertTrue(reply.waitForExistence(timeout: 8)); reply.tap()
            let scope = app.buttons["compose.visibility"]
            XCTAssertTrue(scope.waitForExistence(timeout: 8)); XCTAssertEqual(scope.value as? String, "关注者")
            XCTAssertTrue(app.staticTexts["回复不会扩大原帖的可见范围；可以选择更严格的范围。"].exists)
            capture(app, dark ? "reply-privacy-dark" : "reply-privacy-light"); app.terminate()
        }
    }
    func testPendingFollowCanCancelWithoutCreatingAnotherRequest() {
        let app = launch(["--pending-follow-preview"])
        let author = app.buttons["note.author.at4tltest0025"].firstMatch
        XCTAssertTrue(author.waitForExistence(timeout: 8)); author.tap()
        let follow = app.buttons["profile.follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 8)); XCTAssertEqual(follow.label, "取消关注申请")
        capture(app, "profile-pending-request")
        follow.tap()
        let keep = app.alerts.firstMatch.buttons.matching(identifier: "profile.keepFollow").firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 5)); keep.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(follow.label, "取消关注申请")
        follow.tap(); let confirm = app.alerts.firstMatch.buttons.matching(identifier: "profile.confirmFollow").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "申请关注"), object: follow)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 8), .completed)
        capture(app, "profile-request-cancelled"); app.terminate()
    }
    private func assertReadonlyComposer(_ app: XCUIApplication, _ name: String) {
        let input = app.textViews["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["当前账号的聊天为只读，不能发送消息或创建聊天。"].exists)
        input.tap()
        let noKeyboard = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.keyboards.firstMatch)
        noKeyboard.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [noKeyboard], timeout: 1.5), .completed)
        XCTAssertTrue(app.buttons["chat.send"].exists)
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        for label in ["文件与语音", "录制语音", "添加图片或视频", "插入表情"] {
            let control = app.buttons[label]
            XCTAssertTrue(control.exists, label); XCTAssertFalse(control.isEnabled, label)
        }
        capture(app, name)
    }
    func testReadonlyChatHasClearReasonAndDisabledStart() {
        let app = launch(["--chat-readonly"]); puboSelectTab(app, "消息")
        XCTAssertFalse(app.buttons["chat.start"].exists, "The removed start-chat entry must not return")
        XCTAssertTrue(app.staticTexts["chat.availability"].exists)
        let conversation = app.buttons["conversation.user:syntheticpeer"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 8)); conversation.tap()
        assertReadonlyComposer(app, "chat-readonly-existing-conversation")
        app.navigationBars.buttons.firstMatch.tap()
        puboTapVisible(app, "messages.add"); puboTapVisible(app, "messages.addUsername")
        let username = app.textFields["addFriend.username"]
        XCTAssertTrue(username.waitForExistence(timeout: 8)); username.tap(); username.typeText("friend")
        puboTapVisible(app, "addFriend.search")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        puboTapVisible(app, "addFriend.result.syntheticpeer")
        let start = app.buttons["发送私信"]
        for _ in 0..<6 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.waitForExistence(timeout: 8)); XCTAssertTrue(start.isHittable); start.tap()
        assertReadonlyComposer(app, "chat-readonly-username-profile-path")
        app.terminate()
    }
    func testChatSearchEmptyIsNotAnErrorOrUnfinishedQuery() {
        let app = launch(); puboSelectTab(app, "消息")
        let query = app.textFields["chat.search.query"]; XCTAssertTrue(query.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["chat.search.empty"].exists)
        query.tap(); query.typeText("no-such-message-141")
        XCTAssertTrue(app.staticTexts["chat.search.empty"].waitForExistence(timeout: 8))
        capture(app, "chat-search-empty"); app.terminate()
    }
}
