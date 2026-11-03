import XCTest

final class HomeMotionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func pause(_ seconds: TimeInterval) { _ = XCTWaiter.wait(for: [XCTestExpectation(description: "observe animation")], timeout: seconds) }

    func testOrdinaryHomeMotionAndClickTargets() {
        for dark in [false, true] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--fixture-tab-avatar", "--home-motion"] + (dark ? ["--dark"] : []); app.launch()
            let song = app.buttons["home.song.fixturesong"]
            XCTAssertTrue(song.waitForExistence(timeout: 15))
            XCTAssertFalse(app.buttons["修改公告"].exists); XCTAssertFalse(app.buttons["暂停"].exists)
            capture(app, dark ? "motion-home-dark" : "motion-home-light"); pause(4)
            // Pulling the real list refreshes isolated API data and moves stable song rows.
            let list = app.collectionViews.firstMatch
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            start.press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
            pause(3); capture(app, dark ? "motion-home-refreshed-dark" : "motion-home-refreshed-light")
            song.tap(); XCTAssertTrue(app.buttons["chart.sheet.close"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["7 天最佳"].exists)
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'KST'")).firstMatch.exists)
            pause(2); capture(app, dark ? "motion-song-dark" : "motion-song-light")
            app.buttons["chart.sheet.close"].tap(); XCTAssertTrue(song.waitForExistence(timeout: 5))
            app.buttons["home.chartDetail"].tap(); XCTAssertTrue(app.navigationBars["Melon TOP100"].waitForExistence(timeout: 5))
            capture(app, dark ? "motion-chart-dark" : "motion-chart-light")
            app.buttons["chart.song.fixturesong"].tap(); XCTAssertTrue(app.buttons["chart.sheet.close"].waitForExistence(timeout: 5)); app.buttons["chart.sheet.close"].tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let timestamp = app.buttons["note.timestamp.fixturepost002"]
            for _ in 0..<4 where !timestamp.isHittable { app.swipeUp() }
            XCTAssertTrue(timestamp.isHittable); timestamp.tap(); XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["home.more"].tap(); app.buttons["站内公告"].tap()
            XCTAssertTrue(app.buttons["announcements.open.fixtureannouncement"].waitForExistence(timeout: 5))
            capture(app, dark ? "motion-announcements-dark" : "motion-announcements-light")
            app.buttons["announcements.open.fixtureannouncement"].tap()
            XCTAssertTrue(app.staticTexts["这是隔离测试公告，不会发布到生产。"].waitForExistence(timeout: 5))
            capture(app, dark ? "motion-announcement-detail-dark" : "motion-announcement-detail-light")
            app.navigationBars.buttons.element(boundBy: 0).tap(); app.segmentedControls.buttons["历史公告"].tap()
            XCTAssertTrue(app.buttons["announcements.open.fixturepast"].waitForExistence(timeout: 5)); pause(2)
            app.terminate()
        }
    }
    func testReducedMotionKeepsAnnouncementAccessibleAndSongDismissible() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--home-motion", "--reduce-motion"]; app.launch()
        let announcement = app.buttons["home.announcement.fixtureannouncement"]
        XCTAssertTrue(announcement.waitForExistence(timeout: 15)); announcement.tap()
        XCTAssertTrue(app.staticTexts["这是隔离测试公告，不会发布到生产。"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["home.song.fixturesong"].tap(); XCTAssertTrue(app.buttons["chart.sheet.close"].waitForExistence(timeout: 5))
        app.buttons["chart.sheet.close"].tap(); XCTAssertTrue(app.buttons["home.song.fixturesong"].waitForExistence(timeout: 5))
        capture(app, "home-reduced-motion")
    }
}
