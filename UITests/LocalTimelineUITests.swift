import XCTest

final class LocalTimelineUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--timeline-align", "--gif-preview"] + flags; app.launch()
        XCTAssertTrue(app.buttons["timeline.local"].waitForExistence(timeout: 15)); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
    private func find(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func reveal(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let item = find(app, id)
        for _ in 0..<30 { if item.exists && item.isHittable { return item }; app.swipeUp() }
        return item
    }
    func testFirstLocalAndFourTabsInBothThemes() {
        for dark in [false, true] {
            let app = launch(dark ? ["--dark"] : [])
            XCTAssertTrue(app.buttons["timeline.local"].isSelected)
            XCTAssertTrue(find(app,"note.open.at4tltest0025").waitForExistence(timeout: 10))
            for title in ["动态", "通知", "私信", "我的"] { XCTAssertTrue(app.tabBars.buttons[title].exists) }
            capture(app, dark ? "local-home-dark" : "local-home-light")
            app.buttons["home.more"].tap(); XCTAssertTrue(app.buttons["仅限媒体"].exists); capture(app, dark ? "local-filters-dark" : "local-filters-light")
            app.terminate()
        }
    }
    func testMediaFilterAndSensitiveReveal() {
        let app = launch(); app.buttons["home.more"].tap(); app.buttons["仅限媒体"].tap()
        let hidden = reveal(app,"media.reveal.timelinesensitive"); XCTAssertTrue(hidden.exists)
        XCTAssertFalse(find(app,"media.open.timelinesensitive").exists)
        capture(app,"local-sensitive-hidden"); hidden.tap()
        XCTAssertTrue(find(app,"media.open.timelinesensitive").waitForExistence(timeout: 8)); capture(app,"local-sensitive-revealed")
        app.terminate()
    }
    func testPublicGIFAutomaticallyMovesWithoutControls() {
        let app = launch(); let image = reveal(app,"media.open.timelinegif"); XCTAssertTrue(image.exists)
        let player = find(app,"timeline.animatedImage"); XCTAssertTrue(player.waitForExistence(timeout: 12))
        var frames = Set<String>(); let deadline = Date().addingTimeInterval(3)
        while Date() < deadline { frames.insert(player.value as? String ?? ""); Thread.sleep(forTimeInterval: 0.11) }
        XCTAssertGreaterThan(frames.count,1); XCTAssertFalse(app.buttons["暂停"].exists); capture(app,"local-gif-autoplay")
        app.terminate()
    }
    func testReactionToggleAndReadback() {
        let app = launch(); let reaction = app.buttons["note.reaction.at4tltest0025.❤️"]
        XCTAssertTrue(reaction.waitForExistence(timeout: 10)); reaction.tap()
        XCTAssertTrue(app.buttons["取消反应"].waitForExistence(timeout: 8)); capture(app,"local-reaction-selected")
        reaction.tap(); let cancel = app.buttons["取消反应"].lastMatch; XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        capture(app,"local-reaction-cancelled"); app.terminate()
    }
    func testNewPostsQueueAndReturnToTop() {
        let app = launch(["--timeline-events"])
        app.swipeUp(); app.swipeUp()
        app.buttons["home.more"].tap(); app.buttons["测试新帖"].tap()
        XCTAssertTrue(app.buttons["timeline.newPosts"].waitForExistence(timeout: 5)); capture(app,"local-new-posts-queued")
        app.buttons["timeline.newPosts"].tap()
        XCTAssertTrue(find(app,"note.open.zznewtimeline0001").waitForExistence(timeout: 8)); capture(app,"local-new-posts-shown"); app.terminate()
    }
    func testDeletionClearsReferencedBody() {
        let app = launch(["--timeline-events"])
        _ = reveal(app,"note.open.at4tltest0021")
        app.buttons["home.more"].tap(); app.buttons["测试删除原帖"].tap()
        XCTAssertTrue(find(app,"note.context.unavailable").waitForExistence(timeout: 8)); capture(app,"local-deleted-reference"); app.terminate()
    }
    func testOlderPagesAndLinkClickTargets() {
        let app = launch()
        let oldest = reveal(app,"note.open.at4tltest0001"); XCTAssertTrue(oldest.exists)
        capture(app,"local-history-pagination"); app.terminate()
    }
    func testReducedMotionAndLargeTextKeepFiltersReachable() {
        let app = launch(["--reduce-motion", "--large-text"])
        app.buttons["home.more"].tap(); XCTAssertTrue(app.buttons["显示转帖"].exists)
        capture(app,"local-large-text-filters"); app.terminate()
    }
}
