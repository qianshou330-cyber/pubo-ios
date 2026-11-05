import XCTest

final class TimelineVisualUITests: XCTestCase {
    private let id = "at4tltest0025"
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--timeline-align", "--gif-preview"] + flags
        app.launch()
        XCTAssertTrue(app.buttons["timeline.local"].waitForExistence(timeout: 15))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name
        shot.lifetime = .keepAlways; add(shot)
    }
    private func reveal(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let item = app.descendants(matching: .any).matching(identifier: id).firstMatch
        let scroll = app.scrollViews["timeline.scroll"]
        for _ in 0..<32 {
            let upper = max(110, app.buttons["home.more"].frame.maxY + 12)
            let lower = app.tabBars.firstMatch.frame.minY - 16
            if item.exists && item.isHittable && item.frame.midY > upper && item.frame.midY < lower { return item }
            let reverse = item.exists && item.frame.midY <= upper
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: reverse ? 0.40 : 0.72))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: reverse ? 0.72 : 0.40))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return item
    }
    func testCompactActionTargetsAndBothThemes() {
        for dark in [false, true] {
            let app = launch(dark ? ["--dark"] : [])
            let more = reveal(app, "note.more." + id)
            let buttons = ["note.reply.", "note.renote.", "note.addReaction.", "note.more."].map { app.buttons[$0 + id] }
            for button in buttons {
                XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThanOrEqual(button.frame.width, 43.5)
                XCTAssertGreaterThanOrEqual(button.frame.height, 43.5)
            }
            for i in 1..<buttons.count {
                XCTAssertGreaterThanOrEqual(buttons[i].frame.minX, buttons[i-1].frame.maxX - 0.5)
            }
            if app.frame.width >= 400 { XCTAssertLessThan(more.frame.maxX, app.frame.maxX - 38, "More belongs to the compact row, not the far edge.") }
            capture(app, dark ? "visual-actions-dark" : "visual-actions-light")
            Thread.sleep(forTimeInterval: 7)
            more.tap(); XCTAssertTrue(app.buttons["查看反应详情"].waitForExistence(timeout: 5))
            capture(app, dark ? "visual-note-menu-dark" : "visual-note-menu-light")
            app.terminate()
        }
    }
    func testReplyAndQuoteButtonsOpenTheirOwnComposer() {
        let app = launch()
        reveal(app, "note.reply." + id).tap()
        XCTAssertTrue(app.textViews["compose.text"].waitForExistence(timeout: 8))
        capture(app, "visual-reply-composer")
        app.buttons["compose.close"].tap()
        reveal(app, "note.renote." + id).tap()
        app.buttons["引用转发"].tap()
        XCTAssertTrue(app.textViews["compose.text"].waitForExistence(timeout: 8))
        capture(app, "visual-quote-composer"); app.terminate()
    }
    func testLongHeaderAndMultilineTextRemainReadable() {
        for dark in [false,true] {
            let app = launch(["--timeline-visual-header"] + (dark ? ["--dark"] : []))
            _ = reveal(app, "note.more." + id)
            let author = app.buttons["note.author." + id], time = app.buttons["note.timestamp." + id]
            XCTAssertTrue(author.isHittable); XCTAssertTrue(time.isHittable)
            XCTAssertLessThanOrEqual(author.frame.maxX, time.frame.minX + 1)
            XCTAssertLessThanOrEqual(time.frame.maxX, app.frame.maxX - 12)
            capture(app, dark ? "visual-long-header-dark" : "visual-long-header-light")
            app.terminate()
        }
    }
    func testLargeTextKeepsAllActionsReachable() {
        let app = launch(["--timeline-visual-header", "--large-text", "--reduce-motion", "--dark"])
        for prefix in ["note.reply.", "note.renote.", "note.addReaction.", "note.more."] {
            let button = reveal(app, prefix + id)
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width, 43.5)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX - 8)
        }
        capture(app, "visual-large-text-actions"); app.terminate()
    }
    func testGuestUsesPublicFeedAndCannotReact() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--logged-out", "--timeline-align", "--gif-preview", "--reduce-motion"]
        app.launch()
        XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 15))
        let post = app.descendants(matching: .any).matching(identifier: "note.open." + id).firstMatch
        for _ in 0..<12 where !post.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(post.isHittable); XCTAssertFalse(app.buttons["note.reply." + id].exists)
        capture(app, "visual-guest-public-feed")
        post.tap(); XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 8))
        capture(app, "visual-guest-detail-standard"); app.terminate()
    }
}
