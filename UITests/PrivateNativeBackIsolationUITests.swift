import XCTest

/// Diagnostic control only. The required composer/tool/Back tests remain intact.
final class PrivateNativeBackIsolationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDarkPrivateSecondNativeBackWithoutPicker() { run(afterPicker: false) }
    func testDarkPrivateSecondNativeBackAfterPicker() { run(afterPicker: true) }

    private func run(afterPicker: Bool) {
        let scenario = afterPicker ? "after-picker" : "without-picker"
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--social-align", "--chat-align", "--four-tabs-drafts", "--dark"]
        app.launch()
        defer { app.terminate() }

        let messages = puboTab(app, "消息")
        let row = app.buttons["conversation.user:syntheticpeer"]
        let input = app.textViews["chat.input"]
        let allTabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "app.tab."))
        XCTAssertTrue(messages.waitForExistence(timeout: 20))
        puboSelectTab(app, "消息")

        for visit in 1...2 {
            XCTAssertTrue(row.waitForExistence(timeout: 10), "visit \(visit): missing synthetic conversation")
            for _ in 0..<4 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.isHittable, "visit \(visit): conversation not hittable")
            row.tap()
            XCTAssertTrue(input.waitForExistence(timeout: 10), "visit \(visit): composer never entered")
            XCTAssertTrue(messages.waitForNonExistence(timeout: 5), "visit \(visit): still on home")
            if afterPicker && visit == 1 {
                let attachments = app.buttons["chat.attachments"]
                XCTAssertTrue(attachments.isHittable)
                attachments.tap()
                let drive = app.buttons["从网盘导入"]
                XCTAssertTrue(drive.waitForExistence(timeout: 5), "Drive import action missing")
                drive.tap()
                let cancel = app.buttons["取消"]
                XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Picker Cancel not visible; Back not attempted")
                cancel.tap()
                XCTAssertTrue(input.isHittable, "Composer not restored after Picker Cancel")
            }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.isHittable, "visit \(visit): native Back not hittable")

            // Same native XCUI tap as the required composer gate. No keyboard, route reset,
            // delayed workaround, second tap or edge swipe.
            back.tap()
            let restored = messages.waitForExistence(timeout: 8)
            if !restored {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "private-native-back-dark-\(scenario)-visit-\(visit)-failed"
                shot.lifetime = .keepAlways
                add(shot)
            }
            XCTAssertTrue(restored, "visit \(visit): native Back did not restore Messages")
            XCTAssertEqual(allTabs.count, 4)
            for title in ["消息", "好友", "世界圈", "我的"] {
                XCTAssertTrue(puboTab(app, title).isHittable, "visit \(visit): \(title) not hittable")
            }
            XCTAssertFalse(input.exists, "visit \(visit): private detail still exists after Back")
        }

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "private-native-back-dark-\(scenario)-second-return"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
