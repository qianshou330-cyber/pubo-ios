import XCTest

final class PrivateGIFUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--social-align", "--gif-preview"] + flags; app.launch()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 12)); openPrivate(app); return app
    }
    private func openPrivate(_ app: XCUIApplication) {
        app.tabBars.buttons["私信"].tap(); let peer = app.staticTexts["测试朋友"].firstMatch
        XCTAssertTrue(peer.waitForExistence(timeout: 6)); peer.tap()
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 6))
    }
    private func gif(_ app: XCUIApplication, fullscreen: Bool = false) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: fullscreen ? "private.gif.fullscreen" : "private.gif.inline").firstMatch
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func wait(_ item: XCUIElement, _ predicate: @escaping (String) -> Bool, timeout: TimeInterval = 8) {
        // Avoid sampling exactly once per second: the fixture itself has a one-second cycle.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(item.value as? String ?? "") { return }
            Thread.sleep(forTimeInterval: 0.07)
        }
        XCTFail("GIF did not reach the expected playback state: \(item.value as? String ?? "missing")")
    }
    private func moving(_ image: XCUIElement) {
        XCTAssertTrue(image.waitForExistence(timeout: 8))
        wait(image, { $0.contains("playing=true") })
        let initial = image.value as? String ?? ""
        wait(image, { $0 != initial && $0.contains("playing=true") })
    }
    func testInlineAnimationPauseAndZoomPreviewInBothThemes() {
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            let app = launch(dark ? ["--dark"] : []); let image = gif(app); moving(image)
            wait(image, { $0.contains("frame=0;") }); capture(app, "gif-inline-" + theme + "-frame0")
            wait(image, { $0.contains("frame=1;") }); capture(app, "gif-inline-" + theme + "-frame1")
            XCTAssertTrue((image.value as? String)?.contains("buffer=8388608") == true)
            app.buttons["private.gif.inline.toggle"].tap(); wait(image, { $0.contains("playing=false") })
            let paused = image.value as? String; Thread.sleep(forTimeInterval: 1.1); XCTAssertEqual(image.value as? String, paused)
            capture(app, "gif-paused-" + theme)
            app.buttons["private.gif.inline.toggle"].tap(); moving(image); image.tap()
            let full = gif(app, fullscreen: true); moving(full)
            XCTAssertTrue(app.buttons["attachment.saveFile"].exists); XCTAssertTrue(app.buttons["attachment.savePhoto"].exists)
            capture(app, "gif-fullscreen-" + theme)
            full.pinch(withScale: 1.5, velocity: 1); capture(app, "gif-fullscreen-zoom-" + theme)
            app.buttons["attachment.saveFile"].tap(); XCTAssertTrue(app.buttons["取消"].firstMatch.waitForExistence(timeout: 20)); app.buttons["取消"].firstMatch.tap()
            moving(full); app.buttons["关闭"].tap(); moving(gif(app)); app.terminate()
        }
    }
    func testReduceMotionStartsStillAndExplicitPlayWorks() {
        let app = launch(["--reduce-motion"]); let image = gif(app)
        XCTAssertTrue(image.waitForExistence(timeout: 8)); wait(image, { $0.contains("playing=false") })
        let first = image.value as? String; Thread.sleep(forTimeInterval: 1.1); XCTAssertEqual(image.value as? String, first)
        capture(app, "gif-reduced-motion")
        app.buttons["private.gif.inline.toggle"].tap(); moving(image)
    }
    func testFiniteLoopStopsWithoutBeingRestartedByViewUpdates() {
        let app = launch(["--gif-finite"]); let image = gif(app)
        XCTAssertTrue(image.waitForExistence(timeout: 8)); wait(image, { $0.contains("frame=2;") && $0.contains("loops=2;") && $0.contains("playing=false") }, timeout: 12)
        let final = image.value as? String; Thread.sleep(forTimeInterval: 1.2); XCTAssertEqual(image.value as? String, final)
        capture(app, "gif-finite-stopped")
    }
    func testBackgroundReturnReauthorizesAndDropsRevokedBytes() {
        let app = launch(["--gif-revoke-after-first"]); moving(gif(app))
        XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 1); app.activate()
        XCTAssertTrue(app.buttons["重试图片"].waitForExistence(timeout: 8)); XCTAssertFalse(gif(app).exists)
        capture(app, "gif-revoked-after-background")
    }
    func testCorruptAndOversizedImagesKeepErrorAndSaveEntry() {
        for flag in ["--gif-corrupt", "--gif-too-large"] {
            let app = launch([flag]); XCTAssertTrue(app.buttons["重试图片"].waitForExistence(timeout: 8)); XCTAssertFalse(gif(app).exists)
            XCTAssertTrue(app.buttons["查看与保存附件"].exists); capture(app, "gif-error-" + String(flag.dropFirst(2))); app.terminate()
        }
    }
    func testRecallRemovesInlineAnimation() {
        let app = launch(["--gif-own"]); moving(gif(app))
        app.staticTexts["分享一张 GIF 动图"].press(forDuration: 1); app.buttons["编辑／撤回消息"].tap()
        XCTAssertTrue(app.buttons["撤回消息"].waitForExistence(timeout: 5)); app.buttons["撤回消息"].tap(); app.buttons["撤回消息"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["消息已撤回"].waitForExistence(timeout: 5)); app.buttons["关闭"].tap()
        XCTAssertTrue(gif(app).waitForNonExistence(timeout: 5)); capture(app, "gif-recalled")
    }
    func testAccountSwitchNeverReusesPreviousPrivateImage() {
        let app = launch(["--multi-account-preview"]); moving(gif(app)); app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["我的"].tap(); let link = app.buttons["多账号管理"]
        for _ in 0..<5 where !link.isHittable { app.swipeUp() }; link.tap()
        let second = app.buttons["accounts.select.syntheticsecond"]; XCTAssertTrue(second.waitForExistence(timeout: 5)); second.tap()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 10)); openPrivate(app)
        XCTAssertFalse(gif(app).exists); XCTAssertFalse(app.staticTexts["分享一张 GIF 动图"].exists); capture(app, "gif-switched-account")
    }
    func testStaticPNGAndLargeGIFPreserveBounds() {
        var app = launch(["--gif-static"]); XCTAssertTrue(app.buttons["查看私信图片"].waitForExistence(timeout: 8)); XCTAssertFalse(gif(app).exists); capture(app, "gif-static-png"); app.terminate()
        app = launch(["--gif-large"]); let image = gif(app); moving(image)
        XCTAssertTrue((image.value as? String)?.contains("width=720;") == true)
        XCTAssertTrue((image.value as? String)?.contains("height=405;") == true)
        XCTAssertLessThanOrEqual(image.frame.width, 241); XCTAssertLessThanOrEqual(image.frame.height, 221)
        capture(app, "gif-large-downsampled")
    }
}
