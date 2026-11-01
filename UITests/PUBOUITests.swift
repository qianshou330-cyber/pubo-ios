import XCTest

final class PUBOUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testShellLaunches() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--logged-out"]
        app.launch()
        XCTAssertTrue(app.images["pubo.shell"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testNativeLoginAndFourTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--logged-out"]
        app.launch()
        XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 10))
        app.buttons["auth.openLogin"].tap()
        let username = app.textFields["auth.username"]
        XCTAssertTrue(username.waitForExistence(timeout: 10)); username.tap(); username.typeText("fixture")
        let password = app.secureTextFields["auth.password"]; password.tap(); password.typeText("synthetic-only")
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["动态"].waitForExistence(timeout: 10))
        for title in ["通知", "私信", "我的", "动态"] { app.tabBars.buttons[title].tap(); XCTAssertTrue(app.navigationBars[title].exists) }
        capture(app, "light-timeline")
    }

    func testSecondChatShowsReplyRequired() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reply-required"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 10)); app.tabBars.buttons["私信"].tap()
        app.staticTexts["测试朋友"].firstMatch.tap()
        let input = app.textFields["chat.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("synthetic message")
        app.buttons["chat.send"].tap()
        let error = app.staticTexts["chat.pending.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5)); XCTAssertTrue(error.label.contains("对方未回复之前只能发送一条消息"))
        XCTAssertTrue(app.buttons["手动重试"].exists)
        capture(app, "web-style-chat-reply-required")
    }

    func testSlowEmojiDoesNotBlockLogin() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--logged-out", "--slow"]; app.launch()
        XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 5)); app.buttons["auth.openLogin"].tap()
        XCTAssertTrue(app.buttons["auth.submit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["auth.username"].isEnabled)
    }

    func testNetworkFailureHasRetryAndKeepsTabs() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--network-error"]; app.launch()
        XCTAssertTrue(app.buttons["重试"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["我的"].exists)
    }

    func testContentWarningStaysHidden() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let warning = app.buttons["内容提示"]
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["这段文字需要展开内容警告后查看"].exists)
        warning.tap()
        XCTAssertTrue(app.staticTexts["这段文字需要展开内容警告后查看"].exists)
    }

    func testLostChatReplyReconcilesWithoutNewMessage() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--lost-chat-response"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 10)); app.tabBars.buttons["私信"].tap()
        XCTAssertTrue(app.staticTexts["测试朋友"].firstMatch.waitForExistence(timeout: 5)); app.staticTexts["测试朋友"].firstMatch.tap()
        let input = app.textFields["chat.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("receipt-check")
        app.buttons["chat.send"].tap()
        let check = app.buttons["核对发送结果"]; XCTAssertTrue(check.waitForExistence(timeout: 5)); check.tap()
        XCTAssertTrue(check.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "receipt-check").count, 1)
        capture(app, "chat-reconciled")
    }

    func testLostPostResponseKeepsDraftAndDisablesResubmit() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--lost-post-response"]; app.launch()
        XCTAssertTrue(app.buttons["发帖"].waitForExistence(timeout: 10)); app.buttons["发帖"].tap()
        let editor = app.textViews["compose.text"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let expectedDraft = "synthetic uncertain post"
        // Let each native key event settle on the shared CI simulator. Check every
        // prefix so dropped/reordered input cannot be hidden by the failure UI.
        var entered = ""
        for character in expectedDraft {
            editor.typeText(String(character)); entered.append(character)
            XCTAssertEqual(editor.value as? String, entered)
        }
        app.buttons["compose.send"].tap()
        XCTAssertTrue(app.staticTexts["发送结果待确认"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["compose.send"].isEnabled)
        XCTAssertEqual(editor.value as? String, expectedDraft)
        capture(app, "compose-uncertain")
    }

    func testDarkLargeTextNavigationAndLogout() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--dark", "--large-text"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap()
        capture(app, "dark-large-text-profile")
        let logout = app.buttons["退出登录"]
        for _ in 0..<7 where !logout.isHittable { app.swipeUp() }
        XCTAssertTrue(logout.isHittable); logout.tap()
        let confirmLogout = app.sheets.buttons["退出登录"]
        XCTAssertTrue(confirmLogout.waitForExistence(timeout: 5)); confirmLogout.tap()
        XCTAssertTrue(app.images["pubo.shell"].waitForExistence(timeout: 10))
        capture(app, "dark-logged-out")
    }

    func testWelcomeRegistrationSheetCanCloseAndLogin() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--logged-out"]; app.launch()
        let signup = app.buttons["auth.openRegister"]
        XCTAssertTrue(signup.waitForExistence(timeout: 10)); XCTAssertTrue(signup.isHittable)
        XCTAssertTrue(app.buttons["auth.openLogin"].isHittable)
        capture(app, "web-style-welcome-light")
        signup.tap()
        XCTAssertTrue(app.navigationBars["注册 PUBO"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["再次输入密码"].exists)
        XCTAssertTrue(app.textFields["手机号码"].exists)
        capture(app, "web-style-registration")
        app.buttons["auth.close"].tap()
        XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 5)); app.buttons["auth.openLogin"].tap()
        XCTAssertTrue(app.navigationBars["登录 PUBO"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["再次输入密码"].exists)
    }

    func testWebStyleFeedsAndChatsInBothThemes() {
        for dark in [false, true] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--chat-preview"] + (dark ? ["--dark"] : [])
            app.launch()
            XCTAssertTrue(app.buttons["timeline.global"].waitForExistence(timeout: 10)); app.buttons["timeline.global"].tap()
            XCTAssertTrue(app.buttons["内容提示"].waitForExistence(timeout: 5))
            capture(app, dark ? "web-style-feed-dark" : "web-style-feed-light")
            app.tabBars.buttons["通知"].tap(); XCTAssertTrue(app.staticTexts["测试朋友 关注了你"].waitForExistence(timeout: 5))
            capture(app, dark ? "web-style-notifications-dark" : "web-style-notifications-light")
            app.tabBars.buttons["私信"].tap(); XCTAssertTrue(app.staticTexts["测试朋友"].firstMatch.waitForExistence(timeout: 5))
            capture(app, dark ? "web-style-conversations-dark" : "web-style-conversations-light")
            app.staticTexts["测试朋友"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["你好，欢迎来到 PUBO。"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["收到，我们在这里聊天。"].exists)
            XCTAssertTrue(app.buttons["发送消息"].exists)
            XCTAssertFalse(app.buttons["chat.send"].isEnabled)
            capture(app, dark ? "web-style-chat-dark" : "web-style-chat-light")
            app.terminate()
        }
    }

    func testLargeTextChatKeepsInputAndActionsReachable() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--dark", "--large-text", "--chat-preview"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 10)); app.tabBars.buttons["私信"].tap()
        XCTAssertTrue(app.staticTexts["测试朋友"].firstMatch.waitForExistence(timeout: 5)); app.staticTexts["测试朋友"].firstMatch.tap()
        let input = app.textFields["chat.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("draft")
        let send = app.buttons["chat.send"]
        XCTAssertTrue(send.isHittable); XCTAssertTrue(send.isEnabled)
        XCTAssertEqual(input.value as? String, "draft")
        capture(app, "web-style-chat-large-keyboard")
    }
}

