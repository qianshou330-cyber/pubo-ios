import XCTest

final class AuthVideoUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--logged-out"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 10))
        return app
    }
    private func video(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "auth.videoPlayback").firstMatch }
    private func awaitPlayback(_ app: XCUIApplication, loop: Int = 0) {
        let element = video(app)
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        let predicate = NSPredicate { object, _ in
            guard let value = (object as? XCUIElement)?.value as? String else { return false }
            let parts = value.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && parts[0] >= loop && parts[1] > 600
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: loop > 0 ? 18 : 8), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testBundledVideoLoopsAndLoginRemainsUsable() {
        let app = launch()
        awaitPlayback(app); capture(app, "video-welcome-light")
        awaitPlayback(app, loop: 1); capture(app, "video-loop-light")
        app.buttons["auth.backgroundToggle"].tap()
        XCTAssertTrue(video(app).waitForNonExistence(timeout: 5)); capture(app, "video-paused-light")
        app.buttons["auth.backgroundToggle"].tap(); awaitPlayback(app)
        app.buttons["auth.openLogin"].tap()
        XCTAssertTrue(app.textFields["auth.username"].waitForExistence(timeout: 5)); awaitPlayback(app)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "auth.videoPlayback").count, 1)
        capture(app, "video-login-light")
        app.textFields["auth.username"].tap(); app.textFields["auth.username"].typeText("fixture")
        app.buttons["auth.loginContinue"].tap()
        XCTAssertTrue(app.secureTextFields["auth.password"].waitForExistence(timeout: 5)); capture(app, "video-password-keyboard-light")
        app.secureTextFields["auth.password"].tap(); app.secureTextFields["auth.password"].typeText("synthetic-only")
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["动态"].waitForExistence(timeout: 10))
        XCTAssertFalse(video(app).exists)
    }
    func testDarkVideoReturnsFromBackgroundAndRegistrationIsStatic() {
        let app = launch(["--dark"])
        awaitPlayback(app); capture(app, "video-welcome-dark")
        XCUIDevice.shared.press(.home); app.activate(); awaitPlayback(app)
        app.buttons["auth.openLogin"].tap(); awaitPlayback(app); capture(app, "video-login-dark")
        app.buttons["auth.close"].tap(); awaitPlayback(app)
        app.buttons["auth.openRegister"].tap()
        XCTAssertTrue(app.navigationBars["注册 PUBO"].waitForExistence(timeout: 5))
        XCTAssertTrue(video(app).waitForNonExistence(timeout: 5))
        capture(app, "video-registration-static-dark")
    }
    func testReducedMotionPowerAndMediaFallbackKeepLoginAvailable() {
        for flag in ["--reduce-motion", "--low-power-preview", "--missing-video-preview"] {
            let app = launch([flag])
            XCTAssertFalse(video(app).exists)
            app.buttons["auth.openLogin"].tap()
            XCTAssertTrue(app.textFields["auth.username"].waitForExistence(timeout: 5))
            XCTAssertFalse(video(app).exists); capture(app, "video-fallback-" + String(flag.dropFirst(2)))
            app.terminate()
        }
    }
}
