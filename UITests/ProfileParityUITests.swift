import XCTest

/// Exercises only local draft state. Never taps Save or uploads profile media.
final class ProfileParityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        let dismiss = app.buttons.matching(identifier: "profile.edit.dismissKeyboard").firstMatch
        if app.keyboards.firstMatch.exists && dismiss.isHittable {
            dismiss.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
        for _ in 0..<10 where !element.isHittable {
            // Stay within the visible form; a screen-wide swipe can land on the keyboard.
            let keyboardY = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
            let top = max(app.navigationBars.firstMatch.frame.maxY + 24, 140)
            let bottom = min(keyboardY - 24, app.frame.maxY - 60)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: upwards ? bottom : top))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: upwards ? top : bottom))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }

    private func replace(_ field: XCUIElement, with text: String, in app: XCUIApplication) {
        XCTAssertTrue(field.isHittable)
        let existing = field.value as? String ?? ""
        let count = existing == field.placeholderValue ? 0 : existing.count
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        // A second tap in an empty field opens the system AutoFill menu and
        // steals input. Only reposition the caret when there is content to clear.
        if count > 0 {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        }
        field.typeText(text)
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 8), .completed)
    }

    private func expectSave(_ save: XCUIElement, enabled: Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == %@", NSNumber(value: enabled)), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    func testProfileDraftValidationAndNewFieldsInBothThemes() {
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--timeline-align"] + (dark ? ["--dark"] : [])
            app.launch()
            let home = app.buttons["我的主页"]
            XCTAssertTrue(home.waitForExistence(timeout: 15)); home.tap()
            let edit = app.buttons["编辑个人资料"]
            XCTAssertTrue(edit.waitForExistence(timeout: 10)); reveal(edit, in: app); edit.tap()

            let name = app.textFields["profile.edit.name"]
            let location = app.textFields["profile.edit.location"]
            let birthday = app.textFields["profile.edit.birthday"]
            let save = app.buttons["profile.edit.save"]
            XCTAssertTrue(name.waitForExistence(timeout: 10))
            XCTAssertTrue(app.textViews["profile.edit.description"].exists)
            XCTAssertTrue(save.exists); expectSave(save, enabled: true)
            reveal(location, in: app); replace(location, with: "Tokyo", in: app)
            reveal(birthday, in: app); replace(birthday, with: "2023-02-29", in: app)
            expectSave(save, enabled: false)
            capture(app, "profile-invalid-birthday-" + theme)
            replace(birthday, with: "2024-02-29", in: app)
            expectSave(save, enabled: true)
            capture(app, "profile-valid-birthday-" + theme)

            reveal(name, in: app, upwards: false)
            replace(name, with: String(repeating: "a", count: 31), in: app)
            expectSave(save, enabled: false)
            capture(app, "profile-name-over-limit-" + theme)
            replace(name, with: String(repeating: "a", count: 30), in: app)
            expectSave(save, enabled: true)
            capture(app, "profile-name-at-limit-" + theme)

            // Dismiss instead of saving: no i/update mutation is submitted.
            app.navigationBars["编辑资料"].buttons["取消"].tap()
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            app.terminate()
        }
    }
}
