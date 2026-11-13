import XCTest

final class HomeMotionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func pause(_ seconds: TimeInterval) { _ = XCTWaiter.wait(for: [XCTestExpectation(description: "observe animation")], timeout: seconds) }

    func testOrdinaryHomeMotionAndClickTargets() {
        for dark in [false, true] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--fixture-tab-avatar", "--home-motion"] + (dark ? ["--dark"] : []); app.launch(); puboOpenDiscovery(app)
            let song = app.buttons["home.song.fixturesong"]
            XCTAssertTrue(song.waitForExistence(timeout: 15))
            XCTAssertTrue(song.label.contains("排名 1"))
            XCTAssertFalse(app.buttons["修改公告"].exists); XCTAssertFalse(app.buttons["暂停"].exists)
            capture(app, dark ? "motion-home-dark" : "motion-home-light"); pause(4)
            // Discovery owns the refreshable chart list; preserve the actual ranking change.
            let list = app.collectionViews.firstMatch
            XCTAssertTrue(list.exists)
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            start.press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
            pause(3); XCTAssertTrue(song.label.contains("排名 4")); capture(app, dark ? "motion-home-refreshed-dark" : "motion-home-refreshed-light")
            song.tap(); XCTAssertTrue(app.buttons["chart.sheet.close"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["7 天最佳"].exists)
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'KST'")).firstMatch.exists)
            XCTAssertTrue(app.staticTexts["来源期次：2026-11-03 16:00 KST"].exists)
            pause(2)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chart.history.plot").firstMatch.waitForExistence(timeout: 8))
            capture(app, dark ? "motion-song-dark" : "motion-song-light")
            app.buttons["chart.sheet.close"].tap(); XCTAssertTrue(song.waitForExistence(timeout: 5))
            app.buttons["home.chartDetail"].tap(); XCTAssertTrue(app.navigationBars["Melon TOP100"].waitForExistence(timeout: 5))
            capture(app, dark ? "motion-chart-dark" : "motion-chart-light")
            app.buttons["chart.song.fixturesong"].tap(); XCTAssertTrue(app.buttons["chart.sheet.close"].waitForExistence(timeout: 5)); app.buttons["chart.sheet.close"].tap()
            app.navigationBars["Melon TOP100"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["发现"].waitForExistence(timeout: 8))
            app.navigationBars["发现"].buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons["world.more"].waitForExistence(timeout: 8))
            let timestamp = app.buttons["note.timestamp.fixturepost002"]
            for _ in 0..<4 where !timestamp.isHittable { app.swipeUp() }
            XCTAssertTrue(timestamp.isHittable); timestamp.tap(); XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["home.more"].waitForExistence(timeout: 5))
            let author = app.buttons["note.author.fixturepost002"]; XCTAssertTrue(author.isHittable); author.tap()
            XCTAssertFalse(app.navigationBars["帖子"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["home.more"].waitForExistence(timeout: 5))
            puboOpenDiscovery(app); puboTapVisible(app, "全部公告")
            XCTAssertTrue(app.buttons["announcements.open.fixtureannouncement"].waitForExistence(timeout: 5))
            capture(app, dark ? "motion-announcements-dark" : "motion-announcements-light")
            app.buttons["announcements.open.fixtureannouncement"].tap()
            XCTAssertTrue(app.staticTexts["欢迎加入 PUBO"].firstMatch.waitForExistence(timeout: 5))
            capture(app, dark ? "motion-announcement-detail-dark" : "motion-announcement-detail-light")
            app.navigationBars.buttons.element(boundBy: 0).tap(); app.segmentedControls.buttons["历史公告"].tap()
            XCTAssertTrue(app.buttons["announcements.open.fixturepast"].waitForExistence(timeout: 5)); pause(2)
            app.terminate()
        }
    }
    func testReducedMotionKeepsAnnouncementAccessibleAndSongDismissible() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--home-motion", "--multiple-announcements", "--reduce-motion"]; app.launch(); puboOpenDiscovery(app)
        let announcement = app.buttons["home.announcement.fixtureannouncement"]
        XCTAssertTrue(announcement.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(announcement.frame.height, 44)
        XCTAssertTrue(announcement.isHittable)
        announcement.tap()
        XCTAssertTrue(app.staticTexts["欢迎加入 PUBO"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["home.song.fixturesong"].tap(); XCTAssertTrue(app.buttons["chart.sheet.close"].waitForExistence(timeout: 5))
        app.buttons["chart.sheet.close"].tap(); XCTAssertTrue(app.buttons["home.song.fixturesong"].waitForExistence(timeout: 5))
        capture(app, "home-reduced-motion")
    }
}
