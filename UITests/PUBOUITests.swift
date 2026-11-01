import XCTest

final class PUBOUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func checkHomeMore(_ app: XCUIApplication, screenshot: String) {
        let more = app.buttons["home.more"]
        XCTAssertTrue(more.isHittable)
        XCTAssertGreaterThanOrEqual(more.frame.width, 44)
        XCTAssertGreaterThanOrEqual(more.frame.height, 44)
        more.tap()
        let policy = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "隐私政策")).firstMatch
        XCTAssertTrue(policy.waitForExistence(timeout: 5))
        capture(app, screenshot)
        // Dismiss outside the menu without following an external link.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap()
        XCTAssertTrue(policy.waitForNonExistence(timeout: 5))
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
        app.buttons["auth.loginContinue"].tap()
        let password = app.secureTextFields["auth.password"]; XCTAssertTrue(password.waitForExistence(timeout: 5)); password.tap(); password.typeText("synthetic-only")
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["动态"].waitForExistence(timeout: 10))
        for title in ["通知", "私信", "我的", "动态"] {
            app.tabBars.buttons[title].tap()
            if title == "动态" { XCTAssertTrue(app.buttons["timeline.home"].exists) }
            else { XCTAssertTrue(app.navigationBars[title].exists) }
        }
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
        XCTAssertTrue(app.buttons["auth.loginContinue"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["timeline.home"].waitForExistence(timeout: 10))
        for _ in 0..<5 where !warning.isHittable { app.swipeUp() }
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["这段文字需要展开内容警告后查看"].exists)
        warning.tap()
        let content = app.staticTexts["这段文字需要展开内容警告后查看"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        XCTAssertEqual(warning.value as? String, "已展开")
        capture(app, "web-style-content-warning-expanded")
        warning.tap()
        XCTAssertTrue(content.waitForNonExistence(timeout: 5))
        XCTAssertEqual(warning.value as? String, "已隐藏")
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

    func testHomePanelsAndChartNavigation() {
        for dark in [false, true] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--fixture-tab-avatar"] + (dark ? ["--dark"] : []); app.launch()
            XCTAssertTrue(app.staticTexts["韩国女团音源榜"].waitForExistence(timeout: 10))
            let announcement = app.buttons["home.announcement.fixtureannouncement"]
            XCTAssertTrue(announcement.waitForExistence(timeout: 10))
            XCTAssertEqual(announcement.label, "欢迎加入 PUBO")
            XCTAssertGreaterThanOrEqual(announcement.frame.height, 44)
            XCTAssertTrue(app.buttons["home.compose"].isHittable)
            XCTAssertFalse(app.navigationBars["动态"].exists)
            XCTAssertTrue(app.buttons["timeline.hybrid"].exists)
            XCTAssertFalse(app.buttons["刷新首页"].exists)
            XCTAssertFalse(app.buttons["我的资料"].exists)
            XCTAssertTrue(app.tabBars.buttons["我的"].isHittable)
            for name in ["timeline.home", "timeline.local", "timeline.hybrid", "timeline.global"] {
                let control = app.buttons[name]
                XCTAssertTrue(control.isHittable, name)
                XCTAssertGreaterThanOrEqual(control.frame.width, 44, name)
                XCTAssertGreaterThanOrEqual(control.frame.height, 44, name)
            }
            capture(app, dark ? "home-h5-dark" : "home-h5-light")
            checkHomeMore(app, screenshot: dark ? "home-more-dark" : "home-more-light")
            announcement.tap()
            XCTAssertTrue(app.navigationBars["站内公告"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["这是隔离测试公告，不会发布到生产。"].exists)
            app.navigationBars.buttons.firstMatch.tap()
            app.buttons["切换榜单"].tap(); app.buttons["Genie 实时榜"].tap()
            XCTAssertTrue(app.staticTexts["Genie 实时榜"].waitForExistence(timeout: 5))
            app.buttons["home.chartDetail"].tap()
            XCTAssertTrue(app.navigationBars["Genie 实时榜"].waitForExistence(timeout: 5))
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chart.song.")).firstMatch.tap()
            XCTAssertTrue(app.staticTexts["按本站采集时间记录"].waitForExistence(timeout: 5))
            capture(app, "home-chart-history-\(dark)")
            app.terminate()
        }
        for dark in [false, true] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--large-text"] + (dark ? ["--dark"] : []); app.launch()
            XCTAssertTrue(app.buttons["timeline.home"].waitForExistence(timeout: 10))
            capture(app, dark ? "home-header-large-dark" : "home-header-large-light")
            checkHomeMore(app, screenshot: dark ? "home-more-large-dark" : "home-more-large-light")
            app.terminate()
        }
    }

    func testSlowPanelsDoNotBlockTimelineOrComposer() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--slow-home-panels"]; app.launch()
        XCTAssertTrue(app.staticTexts["测试用户"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.compose"].isHittable); app.buttons["home.compose"].tap()
        XCTAssertTrue(app.textViews["compose.text"].waitForExistence(timeout: 5))
    }

    func testSkeletonLoadingResolvesIndependently() {
        for dark in [false, true] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--skeleton-loading"] + (dark ? ["--dark"] : []); app.launch()
            let skeleton = app.descendants(matching: .any).matching(identifier: "loading.post").firstMatch
            XCTAssertTrue(skeleton.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["暂时没有帖子"].exists)
            XCTAssertTrue(app.buttons["home.compose"].isHittable)
            capture(app, dark ? "loading-skeleton-dark" : "loading-skeleton-light")
            XCTAssertTrue(app.staticTexts["测试用户"].firstMatch.waitForExistence(timeout: 15))
            XCTAssertTrue(skeleton.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["home.announcement.fixtureannouncement"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testSkeletonFailureAndReducedMotion() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--skeleton-failure"]; app.launch()
        let skeleton = app.descendants(matching: .any).matching(identifier: "loading.post").firstMatch
        XCTAssertTrue(skeleton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["重试"].waitForExistence(timeout: 10))
        XCTAssertTrue(skeleton.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["我的"].isHittable)
        capture(app, "loading-skeleton-failure")
        app.terminate()
        app.launchArguments = ["--ui-testing", "--skeleton-loading", "--reduce-motion", "--dark"]; app.launch()
        XCTAssertTrue(skeleton.waitForExistence(timeout: 5))
        XCTAssertEqual(skeleton.value as? String, "加载中，静态占位")
        capture(app, "loading-skeleton-reduce-motion")
        XCTAssertTrue(app.staticTexts["测试用户"].firstMatch.waitForExistence(timeout: 15))
    }

    func testLaunchSkeletonReleasesAfterAccountRestore() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--slow-startup"]; app.launch()
        let launch = app.descendants(matching: .any).matching(identifier: "loading.launch").firstMatch
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
        capture(app, "loading-launch-skeleton")
        XCTAssertTrue(app.tabBars.buttons["动态"].waitForExistence(timeout: 12))
        XCTAssertTrue(launch.waitForNonExistence(timeout: 5))
    }

    func testAHomePullRefreshAndForegroundRefreshWithoutHeaderButtons() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--refreshable-feed", "--fixture-tab-avatar"]; app.launch()
        let newest = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "刷新样例 ")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["刷新首页"].exists)
        XCTAssertFalse(app.buttons["我的资料"].exists)
        let before = Int(newest.label.split(separator: " ").last ?? "0") ?? 0
        // The short default swipe only partially reveals UIRefreshControl on SE.
        // Pull from below the header to above the tab bar, through the row gutter.
        let list = app.collectionViews.firstMatch
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.20))
            .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.86)))
        // Old rows remain in the list by design. Query the new row instead of
        // holding the original accessibility element and expecting its label to mutate.
        let refreshed = app.staticTexts["刷新样例 \(before + 1)"]
        XCTAssertTrue(refreshed.waitForExistence(timeout: 10))
        capture(app, "home-pull-to-refresh")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.staticTexts["刷新样例 \(before + 2)"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        capture(app, "profile-avatar-tab")
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

    func testComposerH5ToolbarAndVisibilityKeepDraft() {
        for dark in [false, true] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing"] + (dark ? ["--dark"] : []); app.launch()
            XCTAssertTrue(app.buttons["发帖"].waitForExistence(timeout: 10))
            capture(app, dark ? "compose-entry-dark" : "compose-entry-light")
            app.buttons["发帖"].tap()
            let send = app.buttons["compose.send"]
            XCTAssertTrue(send.waitForExistence(timeout: 5)); XCTAssertFalse(send.isEnabled)
            XCTAssertEqual(send.label, "发帖")
            XCTAssertTrue(app.buttons["compose.close"].isHittable)
            XCTAssertTrue(app.buttons["添加图片或视频"].isHittable)
            XCTAssertTrue(app.buttons["插入表情"].isHittable)
            capture(app, dark ? "compose-empty-dark" : "compose-empty-light")
            let visibility = app.buttons["compose.visibility"]
            visibility.tap()
            let followers = app.buttons["关注者"]; XCTAssertTrue(followers.waitForExistence(timeout: 5)); followers.tap()
            XCTAssertEqual(visibility.value as? String, "关注者")
            app.buttons["compose.toggleCW"].tap()
            let cw = app.textFields["compose.cw"]; XCTAssertTrue(cw.waitForExistence(timeout: 5)); cw.tap(); cw.typeText("test warning")
            let editor = app.textViews["compose.text"]; editor.tap()
            for character in "draft" { editor.typeText(String(character)) }
            XCTAssertEqual(editor.value as? String, "draft"); XCTAssertTrue(send.isEnabled)
            app.buttons["收起键盘"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            app.buttons["compose.more"].tap()
            let preview = app.buttons["预览"]; XCTAssertTrue(preview.waitForExistence(timeout: 5)); preview.tap()
            XCTAssertTrue(app.staticTexts["预览"].waitForExistence(timeout: 5))
            XCTAssertEqual(editor.value as? String, "draft")
            capture(app, dark ? "compose-cw-preview-dark" : "compose-cw-preview-light")
            app.buttons["compose.close"].tap()
            XCTAssertTrue(app.tabBars.buttons["动态"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testComposerLargeTextKeyboardControlsRemainReachable() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--dark", "--large-text"]; app.launch()
        XCTAssertTrue(app.buttons["发帖"].waitForExistence(timeout: 10)); app.buttons["发帖"].tap()
        let editor = app.textViews["compose.text"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        for character in "large draft" { editor.typeText(String(character)) }
        XCTAssertEqual(editor.value as? String, "large draft")
        XCTAssertTrue(app.buttons["compose.send"].isHittable)
        XCTAssertTrue(app.buttons["compose.close"].isHittable)
        let keyboardTop = app.keyboards.firstMatch.frame.minY
        capture(app, "compose-large-text-keyboard")
        var toolFailures: [String] = []
        for title in ["添加图片或视频", "内容警告", "插入话题", "插入提及", "收起键盘", "插入表情"] {
            let tool = app.buttons[title]
            if !tool.isHittable { toolFailures.append("\(title): not hittable") }
            if tool.frame.maxY > keyboardTop + 2 { toolFailures.append("\(title): below keyboard top \(tool.frame)") }
            if tool.frame.width < 44 || tool.frame.height < 44 { toolFailures.append("\(title): hit area \(tool.frame)") }
        }
        XCTAssertTrue(toolFailures.isEmpty, toolFailures.joined(separator: "; "))
        app.buttons["compose.close"].tap()
        XCTAssertTrue(app.tabBars.buttons["动态"].waitForExistence(timeout: 5))
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
        for dark in [false, true] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--logged-out"] + (dark ? ["--dark"] : []); app.launch()
            let signup = app.buttons["auth.openRegister"]
            XCTAssertTrue(signup.waitForExistence(timeout: 10)); XCTAssertTrue(signup.isHittable)
            XCTAssertTrue(app.buttons["auth.openLogin"].isHittable)
            capture(app, dark ? "h5-sync-welcome-dark-normal" : "h5-sync-welcome-light-normal")
            signup.tap()
            XCTAssertTrue(app.navigationBars["注册 PUBO"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["auth.registrationContinue"].isEnabled)
            capture(app, dark ? "h5-sync-registration-intro-dark" : "h5-sync-registration-intro-light")
            app.switches["auth.agreeNotes"].tap()
            app.buttons["auth.registrationContinue"].tap()
            XCTAssertTrue(app.textFields["auth.phone"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.secureTextFields["auth.confirmation"].exists)
            XCTAssertFalse(app.buttons["auth.requestCode"].isEnabled)
            capture(app, dark ? "h5-sync-registration-dark" : "h5-sync-registration-light")
            app.buttons["auth.close"].tap()
            XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 5)); app.buttons["auth.openLogin"].tap()
            XCTAssertTrue(app.navigationBars["登录 PUBO"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.secureTextFields["auth.password"].exists)
            capture(app, dark ? "h5-sync-login-username-dark" : "h5-sync-login-username-light")
            let username = app.textFields["auth.username"]; username.tap(); username.typeText("fixture")
            app.buttons["auth.loginContinue"].tap()
            XCTAssertTrue(app.secureTextFields["auth.password"].waitForExistence(timeout: 5))
            capture(app, dark ? "h5-sync-login-password-dark" : "h5-sync-login-password-light")
            app.terminate()
        }
    }

    func testPasswordVisibilityAndAccountChangePreserveSafety() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--logged-out"]; app.launch()
        XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 10)); app.buttons["auth.openLogin"].tap()
        let username = app.textFields["auth.username"]; XCTAssertTrue(username.waitForExistence(timeout: 5)); username.tap(); username.typeText("fixture")
        app.buttons["auth.loginContinue"].tap()
        let password = app.secureTextFields["auth.password"]; XCTAssertTrue(password.waitForExistence(timeout: 5)); password.tap(); password.typeText("synthetic")
        app.buttons["auth.password.visibility"].tap()
        let revealed = app.textFields["auth.password"]; XCTAssertTrue(revealed.waitForExistence(timeout: 5)); XCTAssertEqual(revealed.value as? String, "synthetic")
        app.buttons["auth.password.visibility"].tap()
        XCTAssertTrue(app.secureTextFields["auth.password"].waitForExistence(timeout: 5))
        app.buttons["auth.changeAccount"].tap()
        XCTAssertTrue(app.textFields["auth.username"].waitForExistence(timeout: 5))
        app.buttons["auth.loginContinue"].tap()
        XCTAssertTrue(app.secureTextFields["auth.password"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["auth.submit"].isEnabled)
    }

    func testLargeTextRegistrationKeepsFieldsAndCodeButtonReachable() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--logged-out", "--dark", "--large-text"]; app.launch()
        XCTAssertTrue(app.buttons["auth.openRegister"].waitForExistence(timeout: 10)); app.buttons["auth.openRegister"].tap()
        let notes = app.switches["auth.agreeNotes"]
        for _ in 0..<5 where !notes.isHittable { app.swipeUp() }
        XCTAssertTrue(notes.isHittable); notes.tap()
        let proceed = app.buttons["auth.registrationContinue"]
        for _ in 0..<5 where !proceed.isHittable { app.swipeUp() }
        XCTAssertTrue(proceed.isHittable); proceed.tap()
        let usernameLabel = app.staticTexts["account.label.用户名"]
        XCTAssertTrue(usernameLabel.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(usernameLabel.frame.height, 25, "The modal must inherit accessibility text size, not only switch its layout.")
        let code = app.buttons["auth.requestCode"]
        for _ in 0..<6 where !code.isHittable { app.swipeUp() }
        XCTAssertTrue(code.isHittable); XCTAssertFalse(code.isEnabled)
        capture(app, "h5-sync-registration-accessibility-large")
        let confirm = app.secureTextFields["auth.confirmation"]
        for _ in 0..<5 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.isHittable)
        capture(app, "h5-sync-registration-passwords-accessibility-large")
        app.buttons["auth.close"].tap()
        XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 5)); app.buttons["auth.openLogin"].tap()
        let loginLabel = app.staticTexts["account.label.用户名"]
        XCTAssertTrue(loginLabel.waitForExistence(timeout: 5)); XCTAssertGreaterThan(loginLabel.frame.height, 25)
        capture(app, "h5-sync-login-accessibility-large")
    }

    func testWebStyleFeedsAndChatsInBothThemes() {
        for dark in [false, true] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--chat-preview"] + (dark ? ["--dark"] : [])
            app.launch()
            XCTAssertTrue(app.buttons["timeline.global"].waitForExistence(timeout: 10)); app.buttons["timeline.global"].tap()
            let warning = app.buttons["内容提示"]
            for _ in 0..<4 where !warning.isHittable { app.swipeUp() }
            XCTAssertTrue(warning.waitForExistence(timeout: 5))
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

    func testSearchFavoritesAndOwnNoteDeletion() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap()
        app.buttons["搜索"].tap()
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("PUBO\n")
        XCTAssertTrue(app.staticTexts["欢迎来到 PUBO。原生界面测试 :test:"].waitForExistence(timeout: 5))
        app.buttons["帖子更多操作"].firstMatch.tap(); app.buttons["收藏帖子"].tap()
        XCTAssertTrue(app.staticTexts["已收藏"].waitForExistence(timeout: 5)); capture(app, "social-search-favorite")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["我的收藏"].tap()
        XCTAssertTrue(app.staticTexts["欢迎来到 PUBO。原生界面测试 :test:"].waitForExistence(timeout: 5)); capture(app, "social-favorites")
        app.buttons["帖子更多操作"].firstMatch.tap(); app.buttons["删除帖子"].tap()
        app.buttons["删除帖子"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["欢迎来到 PUBO。原生界面测试 :test:"].waitForExistence(timeout: 2))
    }

    func testPollVoteAndComposePoll() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--social-preview"]; app.launch()
        let choice = app.buttons["poll.choice.0"]
        XCTAssertTrue(app.buttons["home.compose"].waitForExistence(timeout: 10))
        for _ in 0..<5 where !choice.isHittable { app.swipeUp() }
        XCTAssertTrue(choice.isHittable); choice.tap()
        XCTAssertTrue(app.staticTexts["3 票 · 单选"].waitForExistence(timeout: 5)); XCTAssertFalse(choice.isEnabled); capture(app, "social-poll-voted")
        app.buttons["home.compose"].tap(); app.buttons["compose.more"].tap(); app.buttons["添加投票"].tap()
        let first = app.textFields["poll.option.0"]; for _ in 0..<4 where !first.isHittable { app.swipeUp() }
        XCTAssertTrue(first.isHittable); first.tap(); first.typeText("Morning")
        let second = app.textFields["poll.option.1"]; second.tap(); second.typeText("Evening")
        capture(app, "social-compose-poll")
        app.buttons["compose.send"].tap()
        XCTAssertTrue(app.buttons["home.compose"].waitForExistence(timeout: 5))
    }

    func testChatEditRecallAndReactions() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--chat-preview"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 10)); app.tabBars.buttons["私信"].tap()
        app.staticTexts["测试朋友"].firstMatch.tap()
        let sent = app.staticTexts["收到，我们在这里聊天。"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5)); sent.press(forDuration: 1)
        app.buttons["编辑／撤回消息"].tap(); XCTAssertTrue(app.buttons["编辑文字"].waitForExistence(timeout: 5)); app.buttons["编辑文字"].tap()
        let editor = app.textViews["chat.edit.text"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText(" Edited")
        let save = app.buttons["chat.edit.save"]; for _ in 0..<4 where !save.isHittable { app.swipeUp() }; save.tap()
        XCTAssertTrue(app.staticTexts["编辑已保存。"].waitForExistence(timeout: 5)); capture(app, "social-chat-edited")
        app.buttons["撤回消息"].tap(); app.buttons["撤回消息"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["消息已撤回"].waitForExistence(timeout: 5)); app.buttons["关闭"].tap()
        let received = app.staticTexts["你好，欢迎来到 PUBO。"]
        received.press(forDuration: 1); app.buttons["消息反应／举报"].tap()
        XCTAssertTrue(app.buttons["添加反应"].waitForExistence(timeout: 5)); app.buttons["添加反应"].tap()
        XCTAssertTrue(app.buttons["❤️"].waitForExistence(timeout: 5)); app.buttons["❤️"].tap()
        XCTAssertTrue(app.buttons["取消 ❤️"].waitForExistence(timeout: 5)); capture(app, "social-chat-reaction")
        app.buttons["取消 ❤️"].tap()
        XCTAssertFalse(app.buttons["取消 ❤️"].waitForExistence(timeout: 2))
    }

    func testPermissionFailureOffersAuthorizationWithoutLoggingOut() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--permission-denied"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap(); app.buttons["我的收藏"].tap()
        XCTAssertTrue(app.staticTexts["当前授权缺少此功能权限，请到“我的”重新授权；原有草稿会保留。"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let authorize = app.buttons["重新授权（保留草稿）"]; for _ in 0..<5 where !authorize.isHittable { app.swipeUp() }
        XCTAssertTrue(authorize.isHittable); capture(app, "social-reauthorization-entry")
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

