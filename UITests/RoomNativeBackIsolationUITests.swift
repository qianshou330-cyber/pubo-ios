import XCTest

/// Diagnostic control only. The required composer/tool/Back tests remain intact.
final class RoomNativeBackIsolationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLightRoomSecondNativeBackWithoutPicker() { run(afterPicker: false) }
    func testLightRoomSecondNativeBackAfterPicker() { run(afterPicker: true) }

    private var observedApp: XCUIApplication?
    private var stage = "not-launched"
    private var arm = "unknown"

    override func tearDownWithError() throws {
        // Post-outcome evidence only. No extra AX query/screenshot before either tap.
        // XCTest teardown cannot run after hard runner termination; external video
        // and the raw xcresult remain independent fallback evidence.
        if let app = observedApp {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "room-native-back-light-\(arm)-final-\(stage)"
            shot.lifetime = .keepAlways; add(shot)
            let receipt = XCTAttachment(string: "arm=\(arm) stage=\(stage)\nSynthetic room/light only; not a delivered touch-duration or lifecycle proof")
            receipt.name = "room-native-back-stage"; receipt.lifetime = .keepAlways; add(receipt)
            app.terminate()
        }
        observedApp = nil
        try super.tearDownWithError()
    }

    private func run(afterPicker: Bool) {
        let scenario = afterPicker ? "after-picker" : "without-picker"
        arm = scenario
        let app = XCUIApplication()
        observedApp = app
        stage = "launch"
        app.launchArguments = ["--ui-testing", "--social-align", "--chat-align", "--four-tabs-drafts"]
        app.launch()

        let messages = puboTab(app, "消息")
        let row = app.buttons["conversation.room:socialroom"]
        let input = app.textViews["room.input"]
        let allTabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "app.tab."))
        XCTAssertTrue(messages.waitForExistence(timeout: 20))
        puboSelectTab(app, "消息")

        for visit in 1...2 {
            stage = "visit-\(visit)-open"
            XCTAssertTrue(row.waitForExistence(timeout: 10), "visit \(visit): missing synthetic conversation")
            for _ in 0..<4 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.isHittable, "visit \(visit): conversation not hittable")
            row.tap()
            XCTAssertTrue(input.waitForExistence(timeout: 10), "visit \(visit): composer never entered")
            XCTAssertTrue(messages.waitForNonExistence(timeout: 5), "visit \(visit): still on home")
            if afterPicker && visit == 1 {
                stage = "visit-1-picker-open"
                let attachments = app.buttons["room.attachments"]
                XCTAssertTrue(attachments.isHittable)
                attachments.tap()
                let drive = app.buttons["从网盘选择"]
                XCTAssertTrue(drive.waitForExistence(timeout: 5), "Drive import action missing")
                drive.tap()
                stage = "visit-1-picker-cancel"
                let cancel = app.buttons["取消"]
                XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Picker Cancel not visible; Back not attempted")
                cancel.tap()
                XCTAssertTrue(input.isHittable, "Composer not restored after Picker Cancel")
            }
            stage = "visit-\(visit)-back-target"
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.isHittable, "visit \(visit): native Back not hittable")

            // Same native XCUI tap as the required composer gate. No keyboard, route reset,
            // delayed workaround, second tap or edge swipe.
            stage = "visit-\(visit)-back-tap"
            back.tap()
            stage = "visit-\(visit)-back-wait"
            let restored = messages.waitForExistence(timeout: 8)
            if !restored {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "room-native-back-light-\(scenario)-visit-\(visit)-failed"
                shot.lifetime = .keepAlways
                add(shot)
            }
            XCTAssertTrue(restored, "visit \(visit): native Back did not restore Messages")
            stage = "visit-\(visit)-restored-assertions"
            XCTAssertEqual(allTabs.count, 4)
            for title in ["消息", "好友", "世界圈", "我的"] {
                XCTAssertTrue(puboTab(app, title).isHittable, "visit \(visit): \(title) not hittable")
            }
            XCTAssertFalse(input.exists, "visit \(visit): room detail still exists after Back")
        }

        stage = "second-return-completed"
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "room-native-back-light-\(scenario)-second-return"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
