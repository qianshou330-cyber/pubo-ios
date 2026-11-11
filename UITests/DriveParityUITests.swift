import XCTest

/// Only local synthetic files. No production reads, downloads, saves or posts.
final class DriveParityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ flags: [String]) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--timeline-align"] + flags; app.launch(); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func openFile(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 15)); app.tabBars.buttons["我的"].tap()
        let drive = app.buttons["网盘"]; XCTAssertTrue(drive.waitForExistence(timeout: 5)); drive.tap()
        let file = app.staticTexts["敏感测试图片.png"].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 8)); file.tap()
        XCTAssertTrue(app.buttons["drive.preview.request"].waitForExistence(timeout: 5))
    }
    func testSensitivePreviewCancelConfirmAndReopenRequireConsentBothThemes() {
        for dark in [false, true] {
            let app = launch(["--drive-sensitive-preview"] + (dark ? ["--dark"] : [])); openFile(app)
            let request = app.buttons["drive.preview.request"]
            XCTAssertTrue(request.isEnabled); request.tap()
            let cancel = app.alerts.buttons["drive.preview.cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5)); capture(app, dark ? "drive-sensitive-confirm-dark" : "drive-sensitive-confirm-light")
            XCTAssertFalse(app.buttons["attachment.saveFile"].exists); cancel.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.navigationBars["查看附件"].exists)
            request.tap(); let confirm = app.alerts.buttons["drive.preview.confirm"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
            XCTAssertTrue(app.buttons["attachment.saveFile"].waitForExistence(timeout: 10)); capture(app, dark ? "drive-sensitive-revealed-dark" : "drive-sensitive-revealed-light")
            app.navigationBars["查看附件"].buttons["关闭"].tap()
            XCTAssertTrue(request.waitForExistence(timeout: 5)); request.tap()
            XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
            app.terminate()
        }
    }
    func testPreviewRechecksSensitivityInsteadOfTrustingOldList() {
        let app = launch(["--drive-sensitive-late"]); openFile(app)
        app.buttons["drive.preview.request"].tap()
        XCTAssertTrue(app.alerts.buttons["drive.preview.confirm"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["attachment.saveFile"].exists)
        capture(app, "drive-new-sensitive-flag-confirmed")
        app.alerts.buttons["drive.preview.cancel"].tap(); app.terminate()
    }
    func testImagePickerAllowsSensitiveImageOnlyAfterExplicitChoice() {
        checkImagePicker(flag: "--drive-sensitive-preview", suffix: "sensitive-list")
    }
    func testImagePickerRechecksSensitivityInsteadOfTrustingOldList() {
        checkImagePicker(flag: "--drive-sensitive-late", suffix: "stale-list")
    }
    private func checkImagePicker(flag: String, suffix: String) {
        let app = launch([flag])
        let home = app.buttons["我的主页"]; XCTAssertTrue(home.waitForExistence(timeout: 15)); home.tap()
        let edit = app.buttons["编辑个人资料"]; XCTAssertTrue(edit.waitForExistence(timeout: 10))
        for _ in 0..<8 where !edit.isHittable { app.swipeUp() }; XCTAssertTrue(edit.isHittable); edit.tap()
        let avatar = app.buttons["头像"]; XCTAssertTrue(avatar.waitForExistence(timeout: 5))
        for _ in 0..<8 where !avatar.isHittable { app.swipeUp() }; XCTAssertTrue(avatar.isHittable); avatar.tap()
        app.buttons["从网盘选择"].tap()
        let file = app.buttons["drive.select.fixturefile"]; XCTAssertTrue(file.waitForExistence(timeout: 8)); XCTAssertTrue(file.isEnabled); file.tap()
        let cancel = app.alerts.buttons["drive.select.cancel"]; XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(file.isHittable); file.tap(); let confirm = app.alerts.buttons["drive.select.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); capture(app, "drive-image-picker-warning-" + suffix); confirm.tap()
        XCTAssertTrue(app.navigationBars["编辑资料"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["敏感测试图片.png"].waitForExistence(timeout: 5))
        capture(app, "drive-image-selected-draft-only-" + suffix)
        app.navigationBars["编辑资料"].buttons["取消"].tap(); app.terminate()
    }
}
