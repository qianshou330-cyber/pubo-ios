import XCTest

private extension XCTestCase {
    func notificationsApp(_ flags: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--notifications-align"] + flags
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["动态"].waitForExistence(timeout: 15))
        return app
    }

    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func enterNotifications(_ app: XCUIApplication) {
        app.tabBars.buttons["通知"].tap()
        XCTAssertTrue(element("notification.noticetest0032", in: app).waitForExistence(timeout: 10))
    }

    func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func tapVisible(_ identifier: String, in app: XCUIApplication) {
        let target = element(identifier, in: app)
        if !target.waitForExistence(timeout: 2) || !target.isHittable {
            for _ in 0..<10 where !target.isHittable { app.swipeUp() }
        }
        XCTAssertTrue(target.isHittable, "Cannot reach \(identifier)")
        target.tap()
    }

    func choose(_ category: String, title: String, in app: XCUIApplication) {
        let opener = element("notifications.filter", in: app)
        XCTAssertTrue(opener.waitForExistence(timeout: 5))
        opener.tap()
        let entry = element("notifications.filter." + category, in: app)
        let label = app.buttons[title].firstMatch
        let anchor = app.buttons["用户的新帖子"].firstMatch
        _ = entry.waitForExistence(timeout: 1)
        // On some iOS releases system menus expose the label but omit the SwiftUI ID.
        for _ in 0..<10 where !entry.isHittable && !label.isHittable {
            let x = anchor.isHittable ? anchor.frame.midX : app.frame.maxX * 0.64
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: app.frame.height * 0.72))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: app.frame.height * 0.31))
            start.press(forDuration: 0.08, thenDragTo: end)
        }
        let option = entry.isHittable ? entry : label
        XCTAssertTrue(option.isHittable, "Filter is unreachable: \(category)")
        option.tap()
    }

    func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(element("notifications.tab.all", in: app).waitForExistence(timeout: 5))
    }
}

final class NotificationAlignmentUITests: XCTestCase {
    func testThreeTabsAndFilterInBothAppearances() {
        for theme in ["light", "dark"] {
            let app = notificationsApp(theme == "dark" ? ["--dark"] : [])
            enterNotifications(app)
            capture(app, "notifications-all-" + theme)
            element("notifications.filter", in: app).tap()
            XCTAssertTrue(app.buttons["用户的新帖子"].firstMatch.waitForExistence(timeout: 5) || element("notifications.filter.note", in: app).exists)
            capture(app, "notifications-filter-" + theme)
            let reaction = element("notifications.filter.reaction", in: app)
            let entry = reaction.isHittable ? reaction : app.buttons["回应"].firstMatch
            if !entry.isHittable { app.swipeUp() }
            XCTAssertTrue(entry.isHittable)
            entry.tap()
            XCTAssertTrue(element("notification.noticetest0029", in: app).waitForExistence(timeout: 5))
            XCTAssertFalse(element("notification.noticetest0031", in: app).exists)
            capture(app, "notifications-reactions-" + theme)
            choose("follow", title: "关注中", in: app)
            XCTAssertTrue(element("notification.noticetest0031", in: app).waitForExistence(timeout: 5))
            XCTAssertTrue(element("notification.noticetest0029", in: app).waitForNonExistence(timeout: 4))
            capture(app, "notifications-follow-" + theme)
            element("notifications.filter", in: app).tap()
            let byID = element("notifications.filter.clear", in: app)
            let clear = byID.waitForExistence(timeout: 1) ? byID : app.buttons["清除"].firstMatch
            XCTAssertTrue(clear.waitForExistence(timeout: 4))
            clear.tap()
            XCTAssertTrue(element("notification.noticetest0031", in: app).waitForExistence(timeout: 5))
            element("notifications.tab.mentions", in: app).tap()
            XCTAssertTrue(element("note.open.notifmention01", in: app).waitForExistence(timeout: 5))
            XCTAssertTrue(element("note.open.notifdirect001", in: app).exists)
            capture(app, "notifications-mentions-" + theme)
            element("notifications.tab.directNotes", in: app).tap()
            XCTAssertTrue(element("note.open.notifdirect001", in: app).waitForExistence(timeout: 5))
            XCTAssertTrue(element("note.open.notifmention01", in: app).waitForNonExistence(timeout: 4))
            capture(app, "notifications-directNotes-" + theme)
            let note = element("note.open.notifdirect001", in: app)
            note.coordinate(withNormalizedOffset: CGVector(dx: 0.76, dy: 0.5)).tap()
            XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 5))
            goBack(app)
            XCTAssertTrue(element("note.open.notifdirect001", in: app).waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testUnreadAndPullToRefresh() {
        let app = notificationsApp(["--notifications-refresh"])
        let tab = app.tabBars.buttons["通知"]
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "12", "12"), object: tab)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 6), .completed)
        capture(app, "notifications-unread-twelve")
        enterNotifications(app)
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT (value CONTAINS %@ OR label CONTAINS %@)", "12", "12"), object: tab)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 6), .completed)
        let newRow = element("notification.noticetest0033", in: app)
        XCTAssertFalse(newRow.exists)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.51, dy: 0.29))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.51, dy: 0.85))
        start.press(forDuration: 0.12, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertTrue(newRow.waitForExistence(timeout: 8))
        capture(app, "notifications-pull-refreshed")
        element("notifications.markRead", in: app).tap()
        XCTAssertTrue(newRow.waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons.matching(identifier: "notification.noticetest0033").count, 1)
    }

    func testSecondPageAndTerminalCursor() {
        let app = notificationsApp()
        enterNotifications(app)
        tapVisible("notifications.more", in: app)
        let last = element("notification.noticetest0011", in: app)
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        tapVisible("notifications.more", in: app)
        XCTAssertTrue(element("notifications.more", in: app).waitForNonExistence(timeout: 5))
        capture(app, "notifications-page-two")
        XCTAssertEqual(app.buttons.matching(identifier: "notification.noticetest0011").count, 1)
    }

    func testNewNotificationArrivesWhileReadingAtTop() {
        let app = notificationsApp(["--notifications-live"])
        enterNotifications(app)
        let newRow = element("notification.noticetest0033", in: app)
        XCTAssertTrue(newRow.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons.matching(identifier: "notification.noticetest0033").count, 1)
        capture(app, "notifications-live-arrived")
        newRow.tap()
        XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("note.open.notiflive0001", in: app).waitForExistence(timeout: 5))
        goBack(app)
    }

    func testAccessibleTextAndReducedMotionStillNavigate() {
        let app = notificationsApp(["--large-text", "--reduce-motion"])
        enterNotifications(app)
        tapVisible("notification.noticetest0032", in: app)
        XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 5))
        goBack(app)
        capture(app, "notifications-large-type-reduced-motion")
    }
}

final class NotificationRouteUITests: XCTestCase {
    private struct Route {
        let kind: String
        let label: String
        let button: String
        let title: String
        let target: String?
        init(_ kind: String, _ label: String, _ button: String, _ title: String, _ target: String? = nil) {
            self.kind = kind
            self.label = label
            self.button = button
            self.title = title
            self.target = target
        }
    }

    private func exercise(_ routes: [Route]) {
        let app = notificationsApp()
        enterNotifications(app)
        for route in routes {
            XCTContext.runActivity(named: route.kind + " → " + route.title + " → 通知") { _ in
                choose(route.kind, title: route.label, in: app)
                let button = element(route.button, in: app)
                XCTAssertTrue(button.waitForExistence(timeout: 5))
                if route.button.hasPrefix("note.open.") {
                    button.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5)).tap()
                } else { tapVisible(route.button, in: app) }
                XCTAssertTrue(app.navigationBars[route.title].waitForExistence(timeout: 6), route.button)
                if let target = route.target {
                    let match = target.hasPrefix("note.") ? element(target, in: app) : app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", target)).firstMatch
                    XCTAssertTrue(match.waitForExistence(timeout: 6), target)
                }
                capture(app, "notification-route-" + route.button)
                goBack(app)
                XCTAssertTrue(button.waitForExistence(timeout: 5), "Returning must restore the filtered list")
            }
        }
    }

    func testNoteMentionReplyQuoteAndPollDestinations() {
        exercise([
            Route("note", "用户的新帖子", "notification.noticetest0022", "帖子", "note.open.notifnote0001"),
            Route("mention", "提及", "note.open.notifmention01", "帖子", "note.open.notifmention01"),
            Route("reply", "回复", "note.open.notifreply001", "帖子", "note.open.notifreply001"),
            Route("quote", "引用", "note.open.notifquote001", "帖子", "note.open.notifquote001"),
            Route("pollEnded", "问卷调查结束", "notification.noticetest0021", "帖子", "note.open.notifpoll0001"),
        ])
    }

    func testSocialAndGroupedTargets() {
        exercise([
            Route("reaction", "回应", "notification.noticetest0032", "帖子", "note.open.notifmusic001"),
            Route("reaction", "回应", "notification.noticetest0029", "帖子", "note.open.notifmusic001"),
            Route("reaction", "回应", "notification.actor.noticetest0029.syntheticviolet", "个人主页", "@violet"),
            Route("renote", "转贴", "notification.noticetest0025", "帖子", "note.open.notifmusic001"),
            Route("renote", "转贴", "notification.noticetest0024", "帖子", "note.open.notifmusic001"),
            Route("follow", "关注中", "notification.noticetest0031", "个人主页", "@violet"),
            Route("followRequestAccepted", "关注请求已通过", "notification.noticetest0017", "个人主页", "@violet"),
        ])
    }

    func testAccountAndSystemTargets() {
        exercise([
            Route("receiveFollowRequest", "收到关注请求", "notification.noticetest0018", "关注申请", "测试朋友"),
            Route("chatRoomInvitationReceived", "您已被邀请加入群聊", "notification.noticetest0027", "PUBO 音乐交流"),
            Route("achievementEarned", "取得的成就", "notification.noticetest0028", "成就"),
            Route("roleAssigned", "授予的角色", "notification.noticetest0015", "我的主页", "@fixture"),
            Route("scheduledNotePosted", "定时发送成功", "notification.noticetest0020", "帖子", "note.open.notifsched001"),
            Route("scheduledNotePostFailed", "定时发送失败", "notification.noticetest0019", "定时帖子"),
            Route("exportCompleted", "已完成导出", "notification.noticetest0014", "导出文件", "notes-export.json"),
            Route("login", "登录", "notification.noticetest0012", "安全验证", "验证当前账号 @fixture"),
            Route("createToken", "创建访问令牌", "notification.noticetest0011", "服务连接"),
        ])
    }

    func testInformationOnlyRowsAndInlineFollowDecisions() {
        for (action, flags) in [("accept", [] as [String]), ("reject", ["--dark"])] {
            let app = notificationsApp(flags)
            enterNotifications(app)
            for (kind, title, suffix) in [("app", "关联应用的通知", "0016"), ("test", "测试通知", "0013")] {
                choose(kind, title: title, in: app)
                let notice = "noticetest" + suffix
                let info = element("notification.text." + notice, in: app)
                XCTAssertTrue(info.waitForExistence(timeout: 4))
                XCTAssertFalse(app.buttons["notification." + notice].exists)
                info.tap()
                XCTAssertTrue(element("notifications.tab.all", in: app).exists)
                capture(app, "notifications-informational-" + kind + "-" + action)
            }
            choose("receiveFollowRequest", title: "收到关注请求", in: app)
            let decision = element("notification." + action + ".noticetest0018", in: app)
            XCTAssertTrue(decision.waitForExistence(timeout: 5))
            decision.tap()
            let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR enabled == false"), object: decision)
            XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 8), .completed)
            capture(app, "notification-follow-" + action)
            app.terminate()
        }
    }
}
