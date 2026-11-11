import XCTest

/// Uses only FixtureTransport. Search is read-only; creation is never submitted.
final class ChannelParityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func openChannels(denied: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--channel-parity-preview"] + (denied ? ["--channel-create-denied"] : [])
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 15)); app.tabBars.buttons["我的"].tap()
        let more = app.buttons["更多功能"]
        for _ in 0..<8 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable); more.tap()
        let channels = app.buttons["频道"]
        XCTAssertTrue(channels.waitForExistence(timeout: 5)); channels.tap()
        XCTAssertTrue(app.navigationBars["频道"].waitForExistence(timeout: 5))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testChannelCreationEntryRequiresPolicy() {
        let denied = openChannels(denied: true)
        XCTAssertFalse(denied.buttons["collections.create"].exists)
        capture(denied, "channel-create-denied"); denied.terminate()
        let allowed = openChannels()
        XCTAssertTrue(allowed.buttons["collections.create"].exists)
        capture(allowed, "channel-create-allowed"); allowed.terminate()
    }
    func testSearchScopeIsSentToAPIAndEmptyQueryDoesNotShowFakeResults() {
        let app = openChannels()
        app.buttons["collections.mode"].tap()
        app.buttons["搜索"].tap()
        let query = app.textFields["channels.search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["channels.search.prompt"].exists)
        XCTAssertFalse(app.staticTexts["暂无内容"].exists)
        query.tap(); query.typeText("music")
        XCTAssertTrue(app.staticTexts["名称和说明结果"].waitForExistence(timeout: 8))
        app.swipeDown() // Dismiss the keyboard without modifying the request.
        app.segmentedControls["channels.search.scope"].buttons["仅名称"].tap()
        XCTAssertTrue(app.staticTexts["仅名称结果"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["名称和说明结果"].exists)
        capture(app, "channels-name-only-search")
        app.segmentedControls["channels.search.scope"].buttons["名称和说明"].tap()
        XCTAssertTrue(app.staticTexts["名称和说明结果"].waitForExistence(timeout: 8))
        capture(app, "channels-name-description-search"); app.terminate()
    }
}
