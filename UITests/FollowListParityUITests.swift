import XCTest

final class FollowListParityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func open(_ flags: [String] = [], followers: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--timeline-align", "--follow-list-preview"] + flags; app.launch()
        puboSelectTab(app, "我的")
        puboTapVisible(app, "me.profile")
        let relation = app.buttons.matching(NSPredicate(format: "label MATCHES %@", followers ? "关注者 [0-9]+" : "关注 [0-9]+")).firstMatch
        XCTAssertTrue(relation.waitForExistence(timeout: 10))
        for _ in 0..<6 where !relation.isHittable { app.swipeUp() }
        XCTAssertTrue(relation.isHittable); relation.tap(); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testFirstPageRetryClearsErrorAndPaginationReachesLastUser() {
        let app = open(["--follow-list-failure-once"])
        let retry = app.buttons["followList.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10)); retry.tap()
        XCTAssertTrue(app.staticTexts["关系用户 031"].waitForExistence(timeout: 10))
        XCTAssertFalse(retry.exists)
        let more = app.buttons["followList.more"]
        for _ in 0..<15 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable); more.tap()
        let last = app.staticTexts["关系用户 001"]
        for _ in 0..<5 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 8)); XCTAssertFalse(more.exists)
        capture(app, "following-last-page"); app.terminate()
    }
    func testEmptyFollowersAreNotAnErrorOrEndlessLoadMore() {
        let app = open(["--follow-list-empty"], followers: true)
        XCTAssertTrue(app.staticTexts["followList.empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["followList.more"].exists)
        XCTAssertFalse(app.buttons["followList.retry"].exists)
        capture(app, "followers-empty"); app.terminate()
    }
}
