import XCTest

/// Optional synthetic visual/accessibility-label evidence, not a required gate.
final class PrivacySignInNoticeDiagnosticUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNoticeBesideOriginalSwitchInBothThemes() {
        let switchID = "privacy.requireSigninToViewContents"
        let noticeID = "privacy.requireSigninToViewContents.notice"
        let exactNotice = "启用后，未登录的访客无法查看你发布的内容。链接预览、网页嵌入，以及不支持帖子引用的服务器，都不会显示这些内容。已分发到其他服务器的内容，可能不受此限制。"

        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing"] + (dark ? ["--dark"] : [])
            app.launch()
            defer { app.terminate() }

            puboSelectTab(app, "我的")
            puboTapVisible(app, "me.settings")
            puboTapVisible(app, "账号与隐私设置")
            let privacyLink = app.buttons["隐私与内容偏好"]
            XCTAssertTrue(privacyLink.waitForExistence(timeout: 8))
            XCTAssertTrue(privacyLink.isHittable)
            privacyLink.tap()
            let navigationBar = app.navigationBars["隐私与内容偏好"]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 8))

            let originalSwitch = app.switches[switchID]
            let notice = app.staticTexts[noticeID]

            func bothVisible() -> Bool {
                guard originalSwitch.exists, originalSwitch.isEnabled, originalSwitch.isHittable, notice.exists else {
                    return false
                }
                let switchFrame = originalSwitch.frame
                let noticeFrame = notice.frame
                let viewFrame = app.frame
                let top = max(viewFrame.minY, navigationBar.frame.maxY)
                return !switchFrame.isEmpty && !noticeFrame.isEmpty &&
                    viewFrame.contains(switchFrame) && viewFrame.contains(noticeFrame) &&
                    switchFrame.minY >= top && noticeFrame.minY >= switchFrame.maxY
            }

            // Bounded search of the existing lower Form. No switch or Save tap.
            var visible = bothVisible()
            for _ in 0..<6 where !visible {
                app.swipeUp()
                visible = bothVisible()
            }
            XCTAssertTrue(visible, "Original switch and complete notice must share the visible form")
            XCTAssertEqual(originalSwitch.identifier, switchID)
            XCTAssertEqual(notice.identifier, noticeID)
            let actual = notice.label
            XCTAssertEqual(actual, exactNotice)

            let label = XCTAttachment(string: "switchIdentifier=\(originalSwitch.identifier)\nswitchLabel=\(originalSwitch.label)\nnoticeIdentifier=\(notice.identifier)\nnoticeLabel=\(actual)")
            label.name = "privacy-signin-notice-ax-\(theme)"
            label.lifetime = .keepAlways
            add(label)

            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "privacy-signin-notice-\(theme)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
