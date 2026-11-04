import XCTest

final class AuthStaticUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--logged-out", "--auth-static"] + extra; app.launch()
        XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 12)); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.5) // Capture the settled state; the raw recording retains the actual transition.
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<9 where !element.isHittable {
            let content = app.scrollViews["auth.content"].firstMatch
            if element.frame.minY < content.frame.minY { content.swipeDown() } else { content.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    private func type(_ identifier: String, _ value: String, _ app: XCUIApplication, secure: Bool = false) {
        let field = secure ? app.secureTextFields[identifier] : app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 8)); reveal(field, app); field.tap(); field.typeText(value)
        if app.buttons["auth.hideKeyboard"].waitForExistence(timeout: 2) { app.buttons["auth.hideKeyboard"].tap() }
    }
    private func loginPassword(_ app: XCUIApplication, username: String = "fixture") {
        app.buttons["auth.openLogin"].tap(); type("auth.username", username, app)
        app.buttons["auth.loginContinue"].tap(); XCTAssertTrue(app.secureTextFields["auth.password"].waitForExistence(timeout: 8))
    }
    private func signup(_ app: XCUIApplication, restricted: Bool = false, expectsFields: Bool = true) {
        app.buttons["auth.openRegister"].tap()
        if restricted { let rule = app.switches["auth.agreeRules"]; reveal(rule, app); rule.tap(); app.alerts.buttons["同意"].tap() }
        for key in ["auth.agreePolicy", "auth.agreeNotes"] { let toggle = app.switches[key]; reveal(toggle, app); toggle.tap(); app.alerts.buttons["同意"].tap() }
        let next = app.buttons["auth.registrationContinue"]; reveal(next, app); XCTAssertTrue(next.isEnabled); next.tap()
        if expectsFields { XCTAssertTrue(app.textFields["auth.username"].waitForExistence(timeout: 8)) }
    }
    func testStaticWelcomeAndCenteredLoginBothThemes() {
        for dark in [false, true] {
            let app = launch(dark ? ["--dark"] : []); let theme = dark ? "dark" : "light"
            XCTAssertFalse(app.buttons["auth.backgroundToggle"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["auth.videoPlayback"].exists)
            capture(app, "static-welcome-" + theme)
            app.buttons["auth.openLogin"].tap()
            let card = app.descendants(matching: .any).matching(identifier: "auth.dialog").firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            XCTAssertLessThanOrEqual(card.frame.width, 401); XCTAssertLessThanOrEqual(card.frame.height, 451)
            XCTAssertGreaterThanOrEqual(app.buttons["auth.close"].frame.height, 44)
            capture(app, "centered-username-" + theme)
            type("auth.username", "fixture", app); app.buttons["auth.loginContinue"].tap()
            XCTAssertTrue(app.secureTextFields["auth.password"].waitForExistence(timeout: 8)); capture(app, "centered-password-" + theme)
            app.buttons["auth.close"].tap(); app.buttons["auth.openLogin"].tap()
            XCTAssertFalse(app.secureTextFields["auth.password"].exists)
            XCTAssertEqual(app.textFields["auth.username"].value as? String, "用户名")
            app.terminate()
        }
    }
    func testTotpBackupAndAccountChange() {
        for dark in [false, true] {
            let app = launch(["--auth-totp"] + (dark ? ["--dark"] : [])); let theme = dark ? "dark" : "light"
            loginPassword(app); type("auth.password", "synthetic-password", app, secure: true); app.buttons["auth.submit"].tap()
            XCTAssertTrue(app.textFields["auth.otp"].waitForExistence(timeout: 8)); capture(app, "centered-totp-" + theme)
            type("auth.otp", "000000", app); app.buttons["auth.submit"].tap()
            XCTAssertTrue(app.staticTexts["动态验证码或备用码不正确，请重新检查。"].waitForExistence(timeout: 5))
            app.buttons["auth.backup"].tap(); XCTAssertFalse(app.buttons["auth.submit"].isEnabled); capture(app, "centered-backup-" + theme)
            app.buttons["auth.changeAccount"].tap(); XCTAssertTrue(app.textFields["auth.username"].waitForExistence(timeout: 5))
            app.buttons["auth.loginContinue"].tap(); XCTAssertTrue(app.secureTextFields["auth.password"].waitForExistence(timeout: 8)); XCTAssertFalse(app.buttons["auth.submit"].isEnabled)
            app.terminate()
        }
    }
    func testRegistrationRulesFormAndResetBothThemes() {
        for dark in [false, true] {
            let app = launch(dark ? ["--dark"] : []); let theme = dark ? "dark" : "light"
            app.buttons["auth.openRegister"].tap(); capture(app, "centered-rules-" + theme); app.buttons["auth.close"].tap()
            signup(app); capture(app, "centered-signup-" + theme)
            app.buttons["auth.close"].tap(); loginPassword(app)
            let forgot = app.buttons["auth.forgot"]; reveal(forgot, app); forgot.tap()
            XCTAssertTrue(app.buttons["auth.emailReset"].waitForExistence(timeout: 5)); capture(app, "centered-reset-email-" + theme)
            reveal(app.buttons["auth.phoneReset"], app); capture(app, "centered-reset-phone-" + theme)
            app.terminate()
        }
    }
    func testSlowLoginCloseAndRateLimit() {
        let app = launch(["--auth-slow-login"]); app.buttons["auth.openLogin"].tap(); type("auth.username", "fixture", app)
        app.buttons["auth.loginContinue"].tap(); capture(app, "login-loading")
        app.buttons["auth.close"].tap(); app.buttons["auth.openLogin"].tap()
        sleep(5); XCTAssertFalse(app.secureTextFields["auth.password"].exists); XCTAssertTrue(app.textFields["auth.username"].exists)
        type("auth.username", "limited", app); app.buttons["auth.loginContinue"].tap()
        XCTAssertTrue(app.staticTexts["操作过于频繁，请稍后再试。"].waitForExistence(timeout: 9)); capture(app, "login-rate-limit")
    }
    func testPrecheckRaceFailureAndSMSFailure() {
        let app = launch(["--auth-sms-failed"]); signup(app)
        type("auth.username", "slow", app)
        let username = app.textFields["auth.username"]; username.tap(); username.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "taken")
        app.buttons["auth.hideKeyboard"].tap()
        XCTAssertTrue(app.staticTexts["用户名已被使用"].waitForExistence(timeout: 5)); sleep(4)
        XCTAssertTrue(app.staticTexts["用户名已被使用"].exists)
        username.tap(); username.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "failed"); app.buttons["auth.hideKeyboard"].tap()
        XCTAssertTrue(app.buttons["auth.usernameStatus.retry"].waitForExistence(timeout: 5)); capture(app, "signup-precheck-failure")
        type("auth.phone", "+86 199-0000-0001", app); reveal(app.buttons["auth.requestCode"], app); app.buttons["auth.requestCode"].tap()
        XCTAssertTrue(app.staticTexts["短信暂时无法发送，请稍后再试。"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["auth.requestCode"].label, "获取验证码"); XCTAssertTrue(app.buttons["auth.requestCode"].isEnabled)
        capture(app, "signup-sms-failure")
    }
    func testSignupEmailPendingAndSuccessfulSMSCooldown() {
        let app = launch(["--auth-email", "--auth-restricted"]); signup(app, restricted: true)
        type("auth.invitation", "SYNTHETIC-INVITE", app); type("auth.username", "new_fixture", app); type("auth.email", "fixture@example.test", app)
        type("auth.phone", "+86 199-0000-0001", app); reveal(app.buttons["auth.requestCode"], app); app.buttons["auth.requestCode"].tap()
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: app.buttons["auth.requestCode"])
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
        type("auth.sms", "123456", app); type("auth.password", "aA1!abcd", app, secure: true); type("auth.confirmation", "aA1!abcd", app, secure: true)
        reveal(app.buttons["auth.submit"], app); XCTAssertTrue(app.buttons["auth.submit"].isEnabled); app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.staticTexts["注册申请已提交"].waitForExistence(timeout: 5)); capture(app, "signup-email-pending")
        XCTAssertFalse(app.secureTextFields["auth.password"].exists)
    }
    func testPhoneResetAndEmailRequest() {
        let app = launch(); loginPassword(app); reveal(app.buttons["auth.forgot"], app); app.buttons["auth.forgot"].tap()
        type("auth.username", "fixture", app); type("auth.email", "fixture@example.test", app)
        reveal(app.buttons["auth.emailReset"], app); app.buttons["auth.emailReset"].tap()
        XCTAssertTrue(app.staticTexts["申请已提交。若账号与邮箱匹配，请查看邮件，并在网站完成重置。"].waitForExistence(timeout: 5))
        type("auth.phone", "19900000001", app); type("auth.sms", "123456", app)
        type("auth.password", "newPassword123", app, secure: true); type("auth.confirmation", "newPassword123", app, secure: true)
        reveal(app.buttons["auth.phoneReset"], app); app.buttons["auth.phoneReset"].tap()
        XCTAssertTrue(app.buttons["auth.loginContinue"].waitForExistence(timeout: 5)); XCTAssertFalse(app.secureTextFields["auth.password"].exists)
        capture(app, "phone-reset-return-login")
    }
    func testLargeTextKeyboardAndCaptchaBoundary() {
        let app = launch(["--large-text", "--dark", "--auth-captcha"]); signup(app, expectsFields: false)
        XCTAssertTrue(app.links["打开本站注册"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["auth.requestCode"].exists)
        capture(app, "signup-web-verification")
        app.buttons["auth.close"].tap(); app.buttons["auth.openLogin"].tap()
        let input = app.textFields["auth.username"]; reveal(input, app); input.tap(); input.typeText("fixture")
        XCTAssertTrue(app.buttons["auth.close"].isHittable); XCTAssertGreaterThanOrEqual(app.buttons["auth.close"].frame.height, 44)
        capture(app, "login-large-text-keyboard")
        app.buttons["auth.close"].tap(); XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 5))
    }
}
