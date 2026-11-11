import XCTest

final class ParityBatchUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--timeline-align"] + flags; app.launch()
        XCTAssertTrue(app.tabBars.buttons["动态"].waitForExistence(timeout: 15)); return app
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
        let keep = app.alerts.buttons["profile.keepFollow"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5)); keep.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(follow.label, "取消关注申请")
        follow.tap(); let confirm = app.alerts.buttons["profile.confirmFollow"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "申请关注"), object: follow)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 8), .completed)
        capture(app, "profile-request-cancelled"); app.terminate()
    }
    func testReadonlyChatHasClearReasonAndDisabledStart() {
        let app = launch(["--chat-readonly"]); app.tabBars.buttons["私信"].tap()
        let start = app.buttons["chat.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 8)); XCTAssertFalse(start.isEnabled)
        XCTAssertTrue(app.staticTexts["chat.availability"].exists)
        capture(app, "chat-readonly"); app.terminate()
    }
    func testChatSearchEmptyIsNotAnErrorOrUnfinishedQuery() {
        let app = launch(); app.tabBars.buttons["私信"].tap()
        let query = app.textFields["chat.search.query"]; XCTAssertTrue(query.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["chat.search.empty"].exists)
        query.tap(); query.typeText("no-such-message-141")
        XCTAssertTrue(app.staticTexts["chat.search.empty"].waitForExistence(timeout: 8))
        capture(app, "chat-search-empty"); app.terminate()
    }
}
