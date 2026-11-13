import XCTest

/// All requests use FixtureTransport's synthetic account and request pages.
final class FollowRequestParityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func open(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--follow-requests-preview"] + flags; app.launch()
        puboSelectTab(app, "好友")
        puboTapVisible(app, "friends.requests")
        XCTAssertTrue(app.segmentedControls["followRequests.direction"].waitForExistence(timeout: 5)); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func choose(_ title: String, app: XCUIApplication) {
        app.segmentedControls["followRequests.direction"].buttons[title].tap()
    }
    func testRejectAndSentCancellationRequireExplicitConfirmation() {
        let app = open()
        let reject = app.buttons["followRequests.reject.received-031"]
        XCTAssertTrue(reject.waitForExistence(timeout: 10)); reject.tap()
        let keep = app.alerts.firstMatch.buttons.matching(identifier: "followRequests.keep").firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 5)); keep.tap()
        XCTAssertTrue(reject.exists)
        reject.tap(); app.alerts.firstMatch.buttons.matching(identifier: "followRequests.confirm").firstMatch.tap()
        XCTAssertTrue(reject.waitForNonExistence(timeout: 8))
        choose("已发送的申请", app: app)
        let cancel = app.buttons["followRequests.cancel.sent-001"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8)); capture(app, "follow-requests-sent")
        cancel.tap(); app.alerts.firstMatch.buttons.matching(identifier: "followRequests.keep").firstMatch.tap(); XCTAssertTrue(cancel.exists)
        cancel.tap(); app.alerts.firstMatch.buttons.matching(identifier: "followRequests.confirm").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["followRequests.empty"].waitForExistence(timeout: 8))
        capture(app, "follow-request-cancelled"); app.terminate()
    }
    func testSlowSentResponseCannotReplaceReceivedTab() {
        let app = open(["--follow-requests-slow-sent"])
        XCTAssertTrue(app.buttons["followRequests.reject.received-031"].waitForExistence(timeout: 10))
        choose("已发送的申请", app: app)
        choose("收到的申请", app: app)
        XCTAssertTrue(app.buttons["followRequests.reject.received-031"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(app.buttons["followRequests.cancel.sent-001"].exists)
        XCTAssertTrue(app.buttons["followRequests.reject.received-031"].exists)
        capture(app, "follow-requests-switch-stale-response"); app.terminate()
    }
    func testSlowRefreshCannotResurrectRejectedRequest() {
        let app = open(["--follow-requests-slow-refresh"])
        let reject = app.buttons["followRequests.reject.received-031"]
        XCTAssertTrue(reject.waitForExistence(timeout: 10))
        let refresh = app.buttons["followRequests.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5)); refresh.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "followRequests.loading").firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(reject.isHittable); reject.tap()
        app.alerts.firstMatch.buttons.matching(identifier: "followRequests.confirm").firstMatch.tap()
        XCTAssertTrue(reject.waitForNonExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 6)
        XCTAssertFalse(reject.exists)
        XCTAssertTrue(app.buttons["followRequests.reject.received-030"].exists)
        capture(app, "follow-request-rejected-during-refresh"); app.terminate()
    }
    func testUnlockedAccountStartsOnSentRequests() {
        let app = open(["--follow-requests-unlocked"])
        XCTAssertTrue(app.buttons["followRequests.cancel.sent-001"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["followRequests.reject.received-031"].exists)
        capture(app, "follow-requests-unlocked-default"); app.terminate()
    }
}
