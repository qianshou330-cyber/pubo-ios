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
        // Scope native control discovery to the stable identified row.
        if (control.value as? String) != (value ? "1" : "0") {
            // Resolve the concrete, hittable UISwitch within this exact row.
            // Candidate 4's failing dark-theme video stayed unchanged, with no
            // setter event after a coordinate tap. That does not establish a
            // product binding failure. Wait for an actionable native control
            // and perform one ordinary tap; do not retry or bypass the UI.
            var concrete: XCUIElement?
            let actionable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let row = control.frame
                concrete = app.switches.allElementsBoundByIndex.first { candidate in
                    let bounds = candidate.frame
                    return candidate.identifier.isEmpty && bounds.width > 0 &&
                        bounds.height > 0 && bounds.width < row.width * 0.5 &&
                        row.contains(CGPoint(x: bounds.midX, y: bounds.midY)) &&
                        candidate.isEnabled && candidate.isHittable
                }
                return control.isEnabled && control.isHittable && concrete != nil
            }, object: app)
            let ready = XCTWaiter.wait(for: [actionable], timeout: 8)
            let rowState = XCTAttachment(string: control.debugDescription)
            rowState.name = "privacy-switch-before-" + control.identifier
            rowState.lifetime = .keepAlways; add(rowState)
            if let actual = concrete {
                let target = XCTAttachment(string: "enabled=\(actual.isEnabled) hittable=\(actual.isHittable) frame=\(actual.frame)\n" + actual.debugDescription)
                target.name = "privacy-native-switch-target-" + control.identifier
                target.lifetime = .keepAlways; add(target)
            }
            capture(app, "privacy-switch-before-tap-" + control.identifier)
            if ready != .completed {
                let tree = XCTAttachment(string: app.debugDescription)
                tree.name = "privacy-native-switch-not-ready-tree"
                tree.lifetime = .keepAlways; add(tree)
            }
            XCTAssertEqual(ready, .completed, "Expected one enabled, hittable native switch inside the identified row")
            guard ready == .completed, let actual = concrete else { return }
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
