import XCTest

final class ContactPagingParityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func open(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--social-align", "--chat-align", "--contacts-preview"] + flags
        app.launch()
        let tab = app.tabBars.buttons["私信"]; XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
        let contacts = app.buttons["联系人"]; XCTAssertTrue(contacts.waitForExistence(timeout: 10)); contacts.tap()
        return app
    }
    private func group(_ app: XCUIApplication) {
        let name = app.staticTexts["合成联系人分组"]
        XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testGroupListRetryClearsError() {
        let app = open(["--contacts-failure-once"])
        let retry = app.buttons["contacts.retry"]; XCTAssertTrue(retry.waitForExistence(timeout: 10)); retry.tap()
        XCTAssertTrue(app.staticTexts["合成联系人分组"].waitForExistence(timeout: 10)); XCTAssertFalse(retry.exists)
        capture(app, "contacts-list-recovered"); app.terminate()
    }
    func testMemberRetryAndPaginationPreserveServerIDOrder() {
        let app = open(["--contacts-member-failure-once"]); group(app)
        let retry = app.buttons["contactGroup.retry"]; XCTAssertTrue(retry.waitForExistence(timeout: 10)); retry.tap()
        XCTAssertTrue(app.staticTexts["成员 001"].waitForExistence(timeout: 10)); XCTAssertFalse(retry.exists)
        let more = app.buttons["contactGroup.more"]
        for _ in 0..<25 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable); more.tap()
        let last = app.staticTexts["成员 051"]
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        for _ in 0..<3 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable); XCTAssertFalse(more.exists)
        capture(app, "contacts-members-last-page"); app.terminate()
    }
    func testRefreshDuringSlowMemberReadRejectsOldSnapshot() {
        let app = open(["--contacts-slow-first"]); group(app)
        XCTAssertTrue(app.descendants(matching: .any)["contactGroup.loading"].waitForExistence(timeout: 10))
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["成员 001"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 6)
        XCTAssertFalse(app.staticTexts["旧成员 001"].exists)
        XCTAssertTrue(app.staticTexts["成员 001"].exists)
        capture(app, "contacts-refresh-newest-snapshot"); app.terminate()
    }
    func testOlderPageFailureRetriesSameRemainingIDs() {
        let app = open(["--contacts-older-failure-once"]); group(app)
        XCTAssertTrue(app.staticTexts["成员 001"].waitForExistence(timeout: 10))
        let more = app.buttons["contactGroup.more"]
        for _ in 0..<25 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable); more.tap()
        let retry = app.buttons["contactGroup.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        for _ in 0..<3 where !retry.isHittable { app.swipeUp() }
        retry.tap()
        XCTAssertTrue(app.staticTexts["成员 051"].waitForExistence(timeout: 10))
        XCTAssertFalse(more.exists); XCTAssertFalse(retry.exists)
        capture(app, "contacts-older-page-recovered"); app.terminate()
    }
    func testLeavingSlowReadAndReenteringDoesNotPublishOldRows() {
        let app = open(["--contacts-slow-first"]); group(app)
        XCTAssertTrue(app.descendants(matching: .any)["contactGroup.loading"].waitForExistence(timeout: 10))
        let back = app.navigationBars.buttons["联系人"]
        XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
        group(app)
        XCTAssertTrue(app.staticTexts["成员 001"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 6)
        XCTAssertFalse(app.staticTexts["旧成员 001"].exists)
        XCTAssertTrue(app.staticTexts["成员 001"].exists)
        capture(app, "contacts-reentry-newest-snapshot"); app.terminate()
    }

}
