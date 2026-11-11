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
        for _ in 0..<7 where !element.isHittable {
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.isHittable)
        field.tap()
        // Short single-line fields: tapping the trailing edge positions the caret
        // after the current content. Subsequent edits preserve that end position.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let existing = field.value as? String ?? ""
        let count = existing == field.placeholderValue ? 0 : existing.count
        if count > 0 { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count)) }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
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
            reveal(location, in: app); replace(location, with: "Tokyo")
            reveal(birthday, in: app); replace(birthday, with: "2023-02-29")
            expectSave(save, enabled: false)
            capture(app, "profile-invalid-birthday-" + theme)
            replace(birthday, with: "2024-02-29")
            expectSave(save, enabled: true)
            capture(app, "profile-valid-birthday-" + theme)

            reveal(name, in: app, upwards: false)
            replace(name, with: String(repeating: "a", count: 31))
            expectSave(save, enabled: false)
            capture(app, "profile-name-over-limit-" + theme)
            replace(name, with: String(repeating: "a", count: 30))
            expectSave(save, enabled: true)
            capture(app, "profile-name-at-limit-" + theme)

            // Dismiss instead of saving: no i/update mutation is submitted.
            app.navigationBars["编辑资料"].buttons["取消"].tap()
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            app.terminate()
        }
    }
}
