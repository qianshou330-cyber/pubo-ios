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
    private func setSwitch(_ control: XCUIElement, to value: Bool, in app: XCUIApplication) {
        XCTAssertTrue(control.isHittable)
        // The recorded AX tree places one concrete UISwitch beneath the
        // identified SwiftUI row. Resolve that descendant, not an anonymous
        // switch from the entire Form (which can be lazily materialized).
        if (control.value as? String) != (value ? "1" : "0") {
            let actual = control.descendants(matching: .switch).firstMatch
            XCTAssertTrue(actual.waitForExistence(timeout: 8))
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: actual)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
            let before = XCTAttachment(string: control.debugDescription)
            before.name = "privacy-switch-before-" + control.identifier
            before.lifetime = .keepAlways; add(before)
            actual.tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value ? "1" : "0"), object: control)
        let outcome = XCTWaiter.wait(for: [changed], timeout: 8)
        if outcome != .completed {
            capture(app, "privacy-switch-failure-" + control.identifier)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "privacy-switch-failure-tree"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertEqual(outcome, .completed)
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
            setSwitch(locked, to: true, in: app); expectEnabled(autoAccept, true)
            setSwitch(autoAccept, to: true, in: app)
            setSwitch(locked, to: false, in: app); expectEnabled(autoAccept, false)
            XCTAssertEqual(autoAccept.value as? String, "1", "Disabling the dependent control must not erase its value")
            capture(app, dark ? "privacy-dependent-disabled-dark" : "privacy-dependent-disabled-light")
            setSwitch(locked, to: true, in: app); expectEnabled(autoAccept, true); XCTAssertEqual(autoAccept.value as? String, "1")
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
