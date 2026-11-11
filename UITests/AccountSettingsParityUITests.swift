import XCTest

final class AccountSettingsParityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func openSettings(_ dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"] + (dark ? ["--dark"] : []); app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap()
        let settings = app.buttons["账号与隐私设置"]
        for _ in 0..<8 where !settings.isHittable { app.swipeUp() }
        XCTAssertTrue(settings.isHittable); settings.tap(); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func setSwitch(_ control: XCUIElement, to value: Bool) {
        XCTAssertTrue(control.isHittable)
        // Tap the actual trailing switch, not a SwiftUI row's label/center.
        if (control.value as? String) != (value ? "1" : "0") {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value ? "1" : "0"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
    }
    private func expectEnabled(_ control: XCUIElement, _ enabled: Bool) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == %@", NSNumber(value: enabled)), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
    }
    func testAutoAcceptRequiresLockedAccountAndRetainsSelectionInBothThemes() {
        for dark in [false, true] {
            let app = openSettings(dark); app.buttons["隐私与内容偏好"].tap()
            let locked = app.switches.matching(identifier: "privacy.isLocked").firstMatch
            let autoAccept = app.switches.matching(identifier: "privacy.autoAcceptFollowed").firstMatch
            XCTAssertTrue(locked.waitForExistence(timeout: 10))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: locked)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            XCTAssertTrue(autoAccept.exists); XCTAssertFalse(autoAccept.isEnabled)
            setSwitch(locked, to: true); expectEnabled(autoAccept, true)
            setSwitch(autoAccept, to: true)
            setSwitch(locked, to: false); expectEnabled(autoAccept, false)
            XCTAssertEqual(autoAccept.value as? String, "1", "Disabling the dependent control must not erase its value")
            capture(app, dark ? "privacy-dependent-disabled-dark" : "privacy-dependent-disabled-light")
            setSwitch(locked, to: true); expectEnabled(autoAccept, true); XCTAssertEqual(autoAccept.value as? String, "1")
            // No save: this test exercises local draft controls only.
            app.terminate()
        }
    }
    func testMissingEmailCapabilityDisablesOnlyEmailControls() {
        // The isolated fixture's meta intentionally omits enableEmail.
        let app = openSettings(); app.buttons["邮箱、密码与动态验证码"].tap()
        let gatePassword = app.secureTextFields["admin.password"]
        XCTAssertTrue(gatePassword.waitForExistence(timeout: 5)); gatePassword.tap(); gatePassword.typeText("synthetic-only")
        app.buttons["admin.authorize"].tap()
        let warning = app.staticTexts["security.email.unavailable"]
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        let address = app.textFields["security.email.address"]
        let save = app.buttons["security.email.save"]
        XCTAssertTrue(address.exists); XCTAssertFalse(address.isEnabled)
        XCTAssertTrue(save.exists); XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.secureTextFields["当前密码"].isEnabled)
        capture(app, "security-email-disabled")
        app.terminate()
    }
}
