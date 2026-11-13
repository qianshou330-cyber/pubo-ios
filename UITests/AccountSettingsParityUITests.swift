import XCTest

final class AccountSettingsParityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func openSettings(_ dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"] + (dark ? ["--dark"] : []); app.launch()
        puboSelectTab(app, "我的")
        puboTapVisible(app, "me.settings")
        puboTapVisible(app, "账号与隐私设置")
        XCTAssertTrue(app.navigationBars["账号与隐私设置"].waitForExistence(timeout: 10))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func setSwitch(_ control: XCUIElement, to value: Bool, in app: XCUIApplication) {
        XCTAssertTrue(control.isHittable)
        let expected = value ? "1" : "0"
        let before = control.value
        let transitionStarted = ProcessInfo.processInfo.systemUptime
        var transition = ["expected=\(expected) before=\(String(describing: before))"]
        // Scope native control discovery to the stable identified row.
        if (before as? String) != expected {
            // C13's AX tree shows one native Switch directly inside this row.
            // Global app.switches enumeration instead re-resolved other rows,
            // including stale indexes, and exhausted the observation budget.
            // Inspect one row snapshot, then tap only its unique native child.
            var concrete: XCUIElement?
            let started = ProcessInfo.processInfo.systemUptime
            var observations: [String] = []
            let actionable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                concrete = nil
                let probeStarted = ProcessInfo.processInfo.systemUptime
                var detail = ""
                defer {
                    let ended = ProcessInfo.processInfo.systemUptime
                    observations.append("elapsed=\(ended - started) queryDuration=\(ended - probeStarted) " + detail)
                }
                do {
                    let row = try control.snapshot()
                    let switches = row.children.filter { $0.elementType == .switch }
                    detail = "row=\(row.frame) rowEnabled=\(row.isEnabled) directSwitches=\(switches.count)"
                    guard switches.count == 1, let native = switches.first else { return false }
                    let bounds = native.frame
                    detail += " nativeID=\(native.identifier) native=\(bounds) nativeEnabled=\(native.isEnabled)"
                    guard row.isEnabled, native.isEnabled, native.identifier.isEmpty,
                          bounds.width > 0, bounds.height > 0,
                          bounds.width < row.frame.width * 0.5,
                          row.frame.contains(bounds) else { return false }
                    let candidate = control.children(matching: .switch).firstMatch
                    let rowHittable = control.isHittable
                    let nativeHittable = candidate.isHittable
                    detail += " rowHittable=\(rowHittable) nativeHittable=\(nativeHittable)"
                    guard rowHittable, nativeHittable else { return false }
                    concrete = candidate
                    return true
                } catch {
                    detail += " snapshotError=\(error)"
                    return false
                }
            }, object: control)
            let ready = XCTWaiter.wait(for: [actionable], timeout: 8)
            let observation = XCTAttachment(string: "timeout=8 outcome=\(ready.rawValue)\n" + observations.joined(separator: "\n"))
            observation.name = "privacy-native-switch-observations-" + control.identifier
            observation.lifetime = .keepAlways; add(observation)
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
            transition.append("tapStarted=\(ProcessInfo.processInfo.systemUptime - transitionStarted)")
            actual.tap()
            transition.append("tapReturned=\(ProcessInfo.processInfo.systemUptime - transitionStarted)")
        }
        // C15's failed transition was 1 -> 0, not a delayed successful 0 -> 1.
        // Keep the same value equality and budget, recording every actual read
        // without triggering XCTest's expensive automatic predicate diagnostics.
        let equalsExpected = NSPredicate(format: "SELF == %@", expected)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let probeStarted = ProcessInfo.processInfo.systemUptime
            let actual = control.value
            let ended = ProcessInfo.processInfo.systemUptime
            transition.append("elapsed=\(ended - transitionStarted) queryDuration=\(ended - probeStarted) actual=\(String(describing: actual))")
            return equalsExpected.evaluate(with: actual)
        }, object: control)
        let outcome = XCTWaiter.wait(for: [changed], timeout: 8)
        let stateEvidence = XCTAttachment(string: "timeout=8 outcome=\(outcome.rawValue)\n" + transition.joined(separator: "\n"))
        stateEvidence.name = "privacy-switch-transition-" + control.identifier + "-expected-" + expected
        stateEvidence.lifetime = .keepAlways; add(stateEvidence)
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
