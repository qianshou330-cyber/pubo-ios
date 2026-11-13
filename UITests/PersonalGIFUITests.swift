import XCTest

final class PersonalGIFUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(reset: Bool = true, flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--social-align", "--gif-preview", "--sticker-testing"] + (reset ? ["--reset-stickers"] : []) + flags; app.launch()
        XCTAssertTrue(puboTab(app, "消息").waitForExistence(timeout: 12)); openChat(app); return app
    }
    private func openChat(_ app: XCUIApplication) { puboSelectTab(app, "消息"); let friend = app.staticTexts["测试朋友"].firstMatch; XCTAssertTrue(friend.waitForExistence(timeout: 8)); friend.tap(); XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 8)) }
    private func collect(_ app: XCUIApplication) {
        let image = app.descendants(matching: .any).matching(identifier: "private.gif.inline").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10)); image.press(forDuration: 1)
        XCTAssertTrue(app.buttons["收藏表情包"].waitForExistence(timeout: 5)); app.buttons["收藏表情包"].tap()
        XCTAssertTrue(app.staticTexts["chat.sticker.notice"].waitForExistence(timeout: 12))
    }
    private func library(_ app: XCUIApplication) { app.buttons["插入表情"].tap(); app.segmentedControls.buttons["GIF 收藏"].tap(); XCTAssertTrue(app.buttons["stickers.import"].waitForExistence(timeout: 5)) }
    private func cells(_ app: XCUIApplication) -> XCUIElementQuery { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stickers.item.'")) }
    private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
    func testLongPressFavoriteDeduplicateAndProtectedAttachmentSend() {
        let app = launch(); collect(app); XCTAssertEqual(app.staticTexts["chat.sticker.notice"].label, "已收藏表情包")
        collect(app); XCTAssertEqual(app.staticTexts["chat.sticker.notice"].label, "已经收藏过这张表情包")
        library(app); XCTAssertEqual(cells(app).count, 1); capture(app, "gif-favorites-light")
        cells(app).firstMatch.tap(); XCTAssertTrue(app.staticTexts["PUBO-sticker.gif"].waitForExistence(timeout: 10)); capture(app, "gif-favorite-ready-to-send")
        app.buttons["移除附件"].tap(); XCTAssertFalse(app.staticTexts["chat.sticker.notice"].exists)
        library(app); cells(app).firstMatch.tap(); XCTAssertTrue(app.staticTexts["PUBO-sticker.gif"].waitForExistence(timeout: 10))
        app.buttons["chat.send"].tap(); XCTAssertTrue(app.staticTexts["PUBO-sticker.gif"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["已读"].firstMatch.waitForExistence(timeout: 10)); XCTAssertFalse(app.staticTexts["chat.pending.error"].exists); XCTAssertFalse(app.staticTexts["chat.sticker.notice"].exists); capture(app, "gif-favorite-sent")
    }
    func testAutomaticCompressionInvalidInputAndRemove() {
        let app = launch(flags: ["--dark", "--sticker-import-testing"]); library(app); app.buttons["stickers.test.large"].tap()
        XCTAssertTrue(app.staticTexts["stickers.notice"].waitForExistence(timeout: 40)); XCTAssertTrue(app.staticTexts["stickers.notice"].label.contains("自动压缩")); XCTAssertEqual(cells(app).count, 1); capture(app, "gif-favorites-compressed-dark")
        app.buttons["stickers.test.invalid"].tap(); XCTAssertTrue(app.staticTexts["stickers.error"].waitForExistence(timeout: 10)); XCTAssertEqual(cells(app).count, 1)
        cells(app).firstMatch.press(forDuration: 1); app.buttons["移除收藏"].tap(); app.buttons["移除收藏"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["还没有收藏的 GIF"].waitForExistence(timeout: 8)); capture(app, "gif-favorites-removed")
    }
    func testRestartPersistenceAndAccountIsolation() {
        var app = launch(flags: ["--multi-account-preview"]); collect(app); app.terminate()
        app = launch(reset: false, flags: ["--multi-account-preview"]); library(app); XCTAssertEqual(cells(app).count, 1); app.buttons["关闭"].tap()
        app.navigationBars.buttons.firstMatch.tap(); puboSelectTab(app, "我的"); let accounts = app.buttons["me.accounts"]
        for _ in 0..<5 where !accounts.isHittable { app.swipeUp() }; accounts.tap()
        let second = app.buttons["accounts.select.syntheticsecond"]; XCTAssertTrue(second.waitForExistence(timeout: 5)); second.tap()
        XCTAssertTrue(puboTab(app, "消息").waitForExistence(timeout: 10)); openChat(app); library(app)
        XCTAssertTrue(app.staticTexts["还没有收藏的 GIF"].waitForExistence(timeout: 5)); XCTAssertEqual(cells(app).count, 0); capture(app, "gif-favorites-other-account")
    }
    func testRevokedSourceCannotBeFavorited() {
        let app = launch(flags: ["--gif-revoke-after-first"]); collect(app)
        XCTAssertFalse(app.staticTexts["chat.sticker.notice"].label.contains("已收藏")); library(app); XCTAssertEqual(cells(app).count, 0); capture(app, "gif-favorites-permission-denied")
    }
    func testRejectedUploadKeepsFavoriteAndShowsError() {
        let app = launch(flags: ["--sticker-upload-denied"]); collect(app); library(app); cells(app).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["chat.error"].waitForExistence(timeout: 10)); XCTAssertFalse(app.staticTexts["PUBO-sticker.gif"].exists)
        library(app); XCTAssertEqual(cells(app).count, 1); capture(app, "gif-favorites-after-rejected-upload")
    }
}
