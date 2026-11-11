import XCTest

final class PUBOUITests: XCTestCase {
    func testAccountDeletionRequiresSameAccountSecuritySession() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap()
        let entry = app.buttons["删除账号"]; for _ in 0..<9 where !entry.isHittable { app.swipeUp() }; XCTAssertTrue(entry.isHittable); entry.tap()
        let password = app.secureTextFields["admin.password"]; XCTAssertTrue(password.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["申请永久删除账号"].exists)
        password.tap(); password.typeText("synthetic-only"); app.buttons["admin.authorize"].tap()
        let delete = app.buttons["申请永久删除账号"]; XCTAssertTrue(delete.waitForExistence(timeout: 5)); XCTAssertFalse(delete.isEnabled)
        capture(app, "account-delete-security-gate")
    }
    func testServiceConnectionUsesAccountReauthenticationAndNativeControls() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch(); openSettings(app)
        let entry = app.buttons["服务连接"]; for _ in 0..<5 where !entry.isHittable { app.swipeUp() }; XCTAssertTrue(entry.isHittable); entry.tap()
        let password = app.secureTextFields["admin.password"]; XCTAssertTrue(password.waitForExistence(timeout: 5)); password.tap(); password.typeText("synthetic-only"); app.buttons["admin.authorize"].tap()
        let create = app.buttons["创建 Webhook"]; XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(app.textFields["接收地址"].waitForExistence(timeout: 5)); XCTAssertTrue(app.secureTextFields["密钥（留空表示不设置）"].exists)
        capture(app, "account-service-connection-empty-form")
    }
    func testNativeNotificationPreferencesSave() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch(); openSettings(app); app.buttons["通知偏好"].tap()
        let picker = app.buttons["notification.preference.follow"]; XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: picker); XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        picker.tap(); app.buttons["不接收"].tap()
        let save = app.buttons["保存通知偏好"]; for _ in 0..<16 where !save.isHittable { app.swipeUp() }; XCTAssertTrue(save.isHittable); save.tap()
        XCTAssertTrue(app.staticTexts["已保存通知偏好"].waitForExistence(timeout: 5)); capture(app, "account-notification-preferences")
    }
    private func enterAdmin(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap()
        let entry = app.buttons["admin.entry"]; for _ in 0..<6 where !entry.isHittable { app.swipeUp() }; XCTAssertTrue(entry.isHittable); entry.tap()
        let password = app.secureTextFields["admin.password"]; XCTAssertTrue(password.waitForExistence(timeout: 5)); password.tap(); password.typeText("synthetic-only"); app.buttons["admin.authorize"].tap()
    }
    func testNativeAdminVerificationListUsesValidFilters() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--admin-preview"]; app.launch(); enterAdmin(app)
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("认证审批")
        let list = app.buttons["admin.operation.admin/verification/list"]; XCTAssertTrue(list.waitForExistence(timeout: 5)); list.tap()
        XCTAssertTrue(app.staticTexts["读取完成；暂无记录。"].waitForExistence(timeout: 5))
        let submit = app.buttons["admin.submit"]; for _ in 0..<8 where !submit.isHittable { app.swipeUp() }; XCTAssertTrue(submit.isHittable)
        capture(app, "admin-empty-verification")
    }
    func testModeratorDoesNotSeeAdminOnlyVerificationOrConfiguration() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--moderator-preview"]; app.launch(); enterAdmin(app)
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("认证审批")
        XCTAssertFalse(app.buttons["admin.operation.admin/verification/list"].exists)
        search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4)); search.typeText("站点配置")
        XCTAssertFalse(app.buttons["admin.operation.admin/update-meta"].exists)
    }
    func testOrdinaryAccountHasNoNativeAdminEntry() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch(); XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap()
        for _ in 0..<5 { XCTAssertFalse(app.buttons["admin.entry"].exists); app.swipeUp() }
    }
    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 15)); app.tabBars.buttons["我的"].tap()
        let settings = app.buttons["账号与隐私设置"]; for _ in 0..<5 where !settings.isHittable { app.swipeUp() }; XCTAssertTrue(settings.isHittable); settings.tap()
    }
    func testNativePrivacyAndVerificationStatus() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch(); openSettings(app)
        app.buttons["认证申请"].tap(); XCTAssertTrue(app.staticTexts["尚未申请"].waitForExistence(timeout: 5)); let submit = app.buttons["提交认证申请"]; for _ in 0..<6 where !submit.exists { app.swipeUp() }; XCTAssertTrue(submit.exists); XCTAssertFalse(submit.isEnabled)
        app.navigationBars.buttons.firstMatch.tap(); app.buttons["隐私与内容偏好"].tap()
        let toggle = app.switches["privacy.hideOnlineStatus"]; XCTAssertTrue(toggle.waitForExistence(timeout: 5)); let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: toggle); XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed); XCTAssertEqual(toggle.value as? String, "0"); toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap(); let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle); XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let save = app.buttons["保存修改"]; for _ in 0..<6 where !save.isHittable { app.swipeUp() }; save.tap(); XCTAssertTrue(app.staticTexts["已保存"].waitForExistence(timeout: 5))
        capture(app, "native-privacy-settings")
    }
    func testNativeInvitationCreationAndReceipt() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch(); openSettings(app); app.buttons["邀请"].tap()
        XCTAssertTrue(app.buttons["创建邀请码"].waitForExistence(timeout: 5)); app.buttons["创建邀请码"].tap(); app.buttons["确认创建"].tap()
        XCTAssertTrue(app.staticTexts["SYNTHETIC-INVITE"].waitForExistence(timeout: 5)); capture(app, "native-invitations")
    }
    func testMultipleAccountsSwitchAndPreserveOtherAccount() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--multi-account-preview"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 15)); app.tabBars.buttons["我的"].tap()
        let link = app.buttons["多账号管理"]; for _ in 0..<5 where !link.isHittable { app.swipeUp() }; link.tap()
        let second = app.buttons["accounts.select.syntheticsecond"]; XCTAssertTrue(second.waitForExistence(timeout: 5)); second.tap()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap(); XCTAssertTrue(app.staticTexts["第二个测试账号"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !link.isHittable { app.swipeUp() }; link.tap(); XCTAssertTrue(app.buttons["accounts.select.syntheticself"].waitForExistence(timeout: 5)); app.buttons["accounts.select.syntheticself"].tap()
        app.tabBars.buttons["我的"].tap()
        let restoredName = app.staticTexts["测试用户"]
        for _ in 0..<8 where !restoredName.isHittable { app.swipeDown() }
        XCTAssertTrue(restoredName.waitForExistence(timeout: 5)); capture(app, "native-account-switch")
        for _ in 0..<5 where !link.isHittable { app.swipeUp() }; link.tap()
        let remove = app.buttons["accounts.remove.syntheticsecond"]; XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        XCTAssertTrue(app.alerts.buttons["取消"].waitForExistence(timeout: 5)); app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["accounts.select.syntheticsecond"].exists); XCTAssertTrue(app.buttons["accounts.select.syntheticself"].exists)
        remove.tap(); app.alerts.buttons["退出这个账号"].tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5)); XCTAssertTrue(app.buttons["accounts.select.syntheticself"].exists)
        XCTAssertFalse(app.buttons["accounts.select.syntheticself"].isEnabled)
    }
    func testNativeContactGroupCreateAndAdd() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reduce-motion"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 10)); app.tabBars.buttons["私信"].tap()
        app.buttons["联系人"].tap(); app.buttons["新建分组"].tap()
        let name = app.alerts.textFields["分组名称"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Native friends")
        app.alerts.buttons["保存"].tap()
        let group = app.staticTexts["Native friends"]; XCTAssertTrue(group.waitForExistence(timeout: 5)); group.tap()
        app.buttons["添加联系人"].tap(); let query = app.textFields["userPicker.query"]; XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("friend")
        app.staticTexts["测试朋友"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["测试朋友"].waitForExistence(timeout: 5)); capture(app, "parity-contact-group")
    }
    func testNativeRoomCreateAndSend() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reduce-motion"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 10)); app.tabBars.buttons["私信"].tap(); app.buttons["chat.start"].tap()
        app.buttons["创建群聊"].tap(); let name = app.textFields["群聊名称"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Native room")
        app.buttons["保存群聊"].tap(); let room = app.staticTexts["Native room"]; XCTAssertTrue(room.waitForExistence(timeout: 5)); room.tap()
        let text = app.textViews["room.input"]; XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("Room proof")
        app.buttons["发送"].tap(); XCTAssertTrue(app.staticTexts["Room proof"].waitForExistence(timeout: 5)); capture(app, "parity-room-message")
    }
    func testNativeClipCreateAndOpenFeed() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reduce-motion"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap(); app.buttons["更多功能"].tap(); app.buttons["剪藏"].tap()
        app.buttons["创建剪藏"].tap(); let name = app.textFields["名称"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Native clip")
        app.buttons["保存"].tap(); let clip = app.staticTexts["Native clip"]; XCTAssertTrue(clip.waitForExistence(timeout: 5)); clip.tap()
        XCTAssertTrue(app.buttons["欢迎来到 PUBO。原生界面测试 :test:"].waitForExistence(timeout: 5)); capture(app, "parity-clip-feed")
    }
    func testNativeDriveFolderCreate() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reduce-motion"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap(); app.buttons["网盘"].tap()
        XCTAssertTrue(app.buttons["网盘新增"].waitForExistence(timeout: 5)); app.buttons["网盘新增"].tap(); app.buttons["新建文件夹"].tap()
        let field = app.alerts.textFields["文件夹名称"]; field.tap(); field.typeText("Native folder"); app.alerts.buttons["创建"].tap()
        XCTAssertTrue(app.staticTexts["Native folder"].waitForExistence(timeout: 5)); capture(app, "parity-drive-folder")
    }
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
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.12)).tap()
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
            else if title == "通知" {
                XCTAssertTrue(app.buttons["notifications.tab.all"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["notification.notice1"].waitForExistence(timeout: 5))
            }
            else { XCTAssertTrue(app.navigationBars[title].exists) }
        }
        capture(app, "light-timeline")
    }

    func testSecondChatShowsReplyRequired() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reply-required"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 10)); app.tabBars.buttons["私信"].tap()
        app.staticTexts["测试朋友"].firstMatch.tap()
        let input = app.textViews["chat.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("synthetic message")
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
        XCTAssertFalse(app.buttons["这段文字需要展开内容警告后查看"].exists)
        warning.tap()
        let content = app.buttons["这段文字需要展开内容警告后查看"]
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
        let input = app.textViews["chat.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("receipt-check")
        app.buttons["chat.send"].tap()
        let check = app.buttons["核对发送结果"]; XCTAssertTrue(check.waitForExistence(timeout: 5)); check.tap()
        XCTAssertTrue(check.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "receipt-check").count, 1)
        capture(app, "chat-reconciled")
    }

    func testHomePanelsAndChartNavigation() {
        for dark in [false, true] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--fixture-tab-avatar", "--reduce-motion"] + (dark ? ["--dark"] : []); app.launch()
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
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Genie 实时榜")).firstMatch.waitForExistence(timeout: 5))
            app.buttons["home.chartDetail"].tap()
            XCTAssertTrue(app.navigationBars["Genie 实时榜"].waitForExistence(timeout: 5))
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chart.song.")).firstMatch.tap()
            XCTAssertTrue(app.staticTexts["7 天最佳"].waitForExistence(timeout: 5))
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
        let newest = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value BEGINSWITH %@", "note.open.refresh", "刷新样例 ")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["刷新首页"].exists)
        XCTAssertFalse(app.buttons["我的资料"].exists)
        guard let text = newest.value as? String,
              let before = Int(text.split(separator: " ").last ?? ""), before > 0 else {
            XCTFail("Refresh fixture must expose its generation in the text view value"); return
        }
        // The short default swipe only partially reveals UIRefreshControl on SE.
        // Pull from below the header to above the tab bar, through the row gutter.
        let list = app.scrollViews["timeline.scroll"]
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.20))
            .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.86)))
        // Old rows remain in the list by design. Query the new row instead of
        // holding the original accessibility element and expecting its text view value to mutate.
        let refreshed = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "note.open.refresh", "刷新样例 \(before + 1)")).firstMatch
        XCTAssertTrue(refreshed.waitForExistence(timeout: 10))
        capture(app, "home-pull-to-refresh")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "note.open.refresh", "刷新样例 \(before + 2)")).firstMatch.waitForExistence(timeout: 10))
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
        // Extra account features make this form longer at accessibility text sizes.
        for _ in 0..<18 where !logout.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38)))
        }
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
            XCTAssertTrue(app.staticTexts["auth.title"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["auth.registrationContinue"].isEnabled)
            capture(app, dark ? "h5-sync-registration-intro-dark" : "h5-sync-registration-intro-light")
            app.switches["auth.agreePolicy"].tap(); app.alerts.buttons["同意"].tap()
            let agree = app.switches["auth.agreeNotes"]; for _ in 0..<4 where !agree.isHittable { app.swipeUp() }; agree.tap(); app.alerts.buttons["同意"].tap()
            let next = app.buttons["auth.registrationContinue"]; for _ in 0..<4 where !next.isHittable { app.swipeUp() }
            app.buttons["auth.registrationContinue"].tap()
            XCTAssertTrue(app.textFields["auth.phone"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.secureTextFields["auth.confirmation"].exists)
            XCTAssertFalse(app.buttons["auth.requestCode"].isEnabled)
            capture(app, dark ? "h5-sync-registration-dark" : "h5-sync-registration-light")
            app.buttons["auth.close"].tap()
            XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 5)); app.buttons["auth.openLogin"].tap()
            XCTAssertTrue(app.staticTexts["auth.title"].waitForExistence(timeout: 5))
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
        let policy = app.switches["auth.agreePolicy"]; for _ in 0..<5 where !policy.isHittable { app.swipeUp() }; XCTAssertTrue(policy.isHittable); policy.tap(); app.alerts.buttons["同意"].tap()
        let notes = app.switches["auth.agreeNotes"]
        for _ in 0..<5 where !notes.isHittable { app.swipeUp() }
        XCTAssertTrue(notes.isHittable); notes.tap(); app.alerts.buttons["同意"].tap()
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
        let loginInput = app.textFields["auth.username"]
        XCTAssertTrue(loginInput.waitForExistence(timeout: 5)); XCTAssertGreaterThan(loginInput.frame.height, 25)
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
            app.tabBars.buttons["通知"].tap()
            // The redesigned row exposes a navigable notification with separate
            // actor and summary text, rather than the former concatenated label.
            let follow = app.buttons["notification.notice1"]
            XCTAssertTrue(follow.waitForExistence(timeout: 5))
            XCTAssertTrue(follow.label.contains("测试朋友"))
            XCTAssertTrue(follow.label.contains("你有新的关注者"))
            XCTAssertTrue(follow.isHittable)
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
        let search = app.textFields["search.query"]; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("PUBO\n")
        XCTAssertTrue(app.buttons["欢迎来到 PUBO。原生界面测试 :test:"].waitForExistence(timeout: 5))
        app.buttons["帖子更多操作"].firstMatch.tap(); app.buttons["收藏帖子"].tap()
        XCTAssertTrue(app.staticTexts["已收藏"].waitForExistence(timeout: 5)); capture(app, "social-search-favorite")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["我的收藏"].tap()
        XCTAssertTrue(app.buttons["欢迎来到 PUBO。原生界面测试 :test:"].waitForExistence(timeout: 5)); capture(app, "social-favorites")
        app.buttons["帖子更多操作"].firstMatch.tap(); app.buttons["删除帖子"].tap()
        app.buttons["删除帖子"].firstMatch.tap()
        let deleted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["欢迎来到 PUBO。原生界面测试 :test:"])
        XCTAssertEqual(XCTWaiter.wait(for: [deleted], timeout: 5), .completed)
    }

    func testSearchPolicyDisabledStillAllowsUserSearch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--search-unavailable"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap(); app.buttons["搜索"].tap()
        XCTAssertTrue(app.staticTexts["search.unavailable"].waitForExistence(timeout: 5))
        let field = app.textFields["search.query"]; field.tap(); field.typeText("PUBO")
        XCTAssertFalse(app.buttons["search.submit"].isEnabled)
        app.buttons["用户"].tap()
        XCTAssertTrue(app.staticTexts["测试朋友"].waitForExistence(timeout: 5))
        capture(app, "social-search-policy")
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
        let remove = app.buttons["chat.reaction.remove.❤"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); capture(app, "social-chat-reaction")
        remove.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: remove)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
    }

    func testPermissionFailureOffersAuthorizationWithoutLoggingOut() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--permission-denied"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap(); app.buttons["我的收藏"].tap()
        XCTAssertTrue(app.staticTexts["当前授权缺少此功能权限，请到“我的”重新授权；原有草稿会保留。"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let authorize = app.buttons["重新授权（保留草稿）"]; for _ in 0..<5 where !authorize.isHittable { app.swipeUp() }
        XCTAssertTrue(authorize.isHittable); capture(app, "social-reauthorization-entry")
    }

    func testChatEditConflictAndLostResponseKeepDraftUntilManualResolution() {
        for conflict in [true, false] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--chat-preview", conflict ? "--edit-conflict" : "--lost-edit-response"]; app.launch()
            XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 10)); app.tabBars.buttons["私信"].tap()
            app.staticTexts["测试朋友"].firstMatch.tap()
            let sent = app.staticTexts["收到，我们在这里聊天。"]
            XCTAssertTrue(sent.waitForExistence(timeout: 5)); sent.press(forDuration: 1)
            app.buttons["编辑／撤回消息"].tap(); XCTAssertTrue(app.buttons["编辑文字"].waitForExistence(timeout: 5)); app.buttons["编辑文字"].tap()
            let editor = app.textViews["chat.edit.text"]; editor.tap(); editor.typeText(" Draft")
            let save = app.buttons["chat.edit.save"]; for _ in 0..<4 where !save.isHittable { app.swipeUp() }; save.tap()
            let error = app.staticTexts["chat.action.error"]; XCTAssertTrue(error.waitForExistence(timeout: 5))
            XCTAssertTrue((editor.value as? String)?.contains("Draft") == true)
            XCTAssertFalse(save.exists)
            capture(app, conflict ? "social-chat-edit-conflict" : "social-chat-edit-uncertain")
            if conflict {
                XCTAssertTrue(app.staticTexts["另一台设备已编辑"].exists)
                XCTAssertTrue(app.buttons["以当前版本继续编辑"].exists)
            } else {
                XCTAssertFalse(app.buttons["以当前版本继续编辑"].exists)
                let check = app.buttons["核对最新状态"]; for _ in 0..<4 where !check.isHittable { app.swipeUp() }; check.tap()
                XCTAssertTrue(app.staticTexts["已核对，编辑已生效。"].waitForExistence(timeout: 5))
                XCTAssertFalse(editor.exists)
            }
            app.terminate()
        }
    }

    func testLargeTextChatKeepsInputAndActionsReachable() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--dark", "--large-text", "--chat-preview"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 10)); app.tabBars.buttons["私信"].tap()
        XCTAssertTrue(app.staticTexts["测试朋友"].firstMatch.waitForExistence(timeout: 5)); app.staticTexts["测试朋友"].firstMatch.tap()
        let input = app.textViews["chat.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("draft")
        let send = app.buttons["chat.send"]
        XCTAssertTrue(send.isHittable); XCTAssertTrue(send.isEnabled)
        XCTAssertEqual(input.value as? String, "draft")
        capture(app, "web-style-chat-large-keyboard")
    }

    func testHistoricalReferenceAndReturnToLatest() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--parity-preview"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 10)); app.tabBars.buttons["私信"].tap()
        app.staticTexts["测试朋友"].firstMatch.tap()
        let quote = app.buttons["chat.reference.chatquote003"]
        XCTAssertTrue(quote.waitForExistence(timeout: 5))
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "历史原消息已更新"), object: quote)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
        quote.tap()
        XCTAssertTrue(app.staticTexts["正在查看历史消息，预取不会标记已读"].waitForExistence(timeout: 5))
        capture(app, "parity-reference-context")
        app.buttons["回到最新消息"].tap()
        XCTAssertTrue(app.staticTexts["正在查看历史消息，预取不会标记已读"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(quote.exists)
    }

    func testChartFallbackSearchAndHistory() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--parity-preview"]; app.launch()
        XCTAssertTrue(app.buttons["home.chartDetail"].waitForExistence(timeout: 10)); app.buttons["home.chartDetail"].tap()
        let song = app.buttons["chart.song.fixturesong"]
        XCTAssertTrue(song.waitForExistence(timeout: 5)); XCTAssertTrue(song.label.contains("下降 1 位"))
        let query = app.textFields["chart.filter.query"]; query.tap(); query.typeText("missing")
        XCTAssertTrue(app.staticTexts["当前筛选没有匹配歌曲"].waitForExistence(timeout: 5)); XCTAssertFalse(song.exists)
        query.tap(); query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7)); query.typeText("NEON\n")
        XCTAssertTrue(song.waitForExistence(timeout: 5)); song.tap()
        XCTAssertTrue(app.staticTexts["7 天最佳"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["变化依据：本站上次可比较记录"].exists)
        capture(app, "parity-chart-history")
    }

    func testGuestSeesPublicFeedAndEmptyAnnouncementsStayHidden() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--logged-out", "--empty-announcements", "--reduce-motion"]; app.launch()
        XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 10))
        let title = app.staticTexts["韩国女团音源榜"]; for _ in 0..<5 where !title.isHittable { app.swipeUp() }
        XCTAssertTrue(title.isHittable)
        XCTAssertFalse(app.staticTexts["暂无公告"].exists); XCTAssertFalse(app.buttons["修改公告"].exists)
        let post = app.descendants(matching: .any).matching(identifier: "note.open.fixturepost002").firstMatch
        for _ in 0..<7 where !post.isHittable { app.swipeUp() }
        XCTAssertTrue(post.isHittable); XCTAssertFalse(app.buttons["添加表情反应"].exists)
        post.tap(); XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 5))
        capture(app, "parity-guest-public-feed")
    }

    func testAdminAnnouncementEditRequiresReauthentication() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--admin-preview", "--reduce-motion"]; app.launch()
        let edit = app.buttons["修改公告"]; XCTAssertTrue(edit.waitForExistence(timeout: 10)); edit.tap()
        app.buttons["announcement.edit.fixtureannouncement"].tap()
        let password = app.secureTextFields["admin.password"]; XCTAssertTrue(password.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["announcement.title"].exists)
        password.tap(); password.typeText("synthetic-only"); app.buttons["admin.authorize"].tap()
        let title = app.textFields["announcement.title"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText(" Edited")
        let save = app.buttons["保存修改"]; for _ in 0..<5 where !save.isHittable { app.swipeUp() }; save.tap()
        XCTAssertTrue(app.buttons["home.announcement.fixtureannouncement"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.announcement.fixtureannouncement"].label.contains("Edited"))
        capture(app, "parity-admin-announcement")
    }

    func testScheduledPostReceiptAndCancel() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reduce-motion"]; app.launch()
        XCTAssertTrue(app.buttons["home.compose"].waitForExistence(timeout: 10)); app.buttons["home.compose"].tap()
        let editor = app.textViews["compose.text"]; editor.tap(); editor.typeText("Scheduled fixture")
        app.buttons["compose.more"].tap(); app.buttons["定时发布"].tap()
        app.buttons["compose.send"].tap()
        XCTAssertTrue(app.buttons["home.compose"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap(); app.buttons["定时帖子"].tap()
        XCTAssertTrue(app.staticTexts["Scheduled fixture"].waitForExistence(timeout: 5)); capture(app, "parity-scheduled-note")
        app.buttons["取消定时，保留服务器草稿"].tap(); app.buttons["取消定时发布"].tap()
        XCTAssertTrue(app.staticTexts["暂无定时帖子"].waitForExistence(timeout: 5))
    }
}


