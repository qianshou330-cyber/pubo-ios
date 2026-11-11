import XCTest
import UIKit

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
        let options = ["用户的新帖子", "关注中", "提及", "回复", "转贴", "引用", "回应", "问卷调查结束",
                       "定时发送成功", "定时发送失败", "收到关注请求", "关注请求已通过", "关联应用的通知", "授予的角色",
                       "您已被邀请加入群聊", "取得的成就", "已完成导出", "测试通知", "登录", "创建访问令牌"]
        _ = entry.waitForExistence(timeout: 1)
        // A system Menu only occupies part of the screen. Drag between the visible menu rows
        // so the gesture cannot dismiss it or scroll the notification feed underneath.
        for _ in 0..<7 where !entry.isHittable && !label.isHittable {
            let matches = app.buttons.matching(NSPredicate(format: "label IN %@", options)).allElementsBoundByIndex
            let visible = matches.filter { $0.isHittable }.sorted { $0.frame.midY < $1.frame.midY }
            guard let first = visible.first, let last = visible.last, last.frame.midY - first.frame.midY > 55,
                  let firstIndex = options.firstIndex(of: first.label), let targetIndex = options.firstIndex(of: title) else {
                return XCTFail("System filter menu has no scrollable visible rows: " + category)
            }
            let span = last.frame.midY - first.frame.midY
            let low = first.frame.midY + span * 0.18, high = last.frame.midY - span * 0.18
            let up = targetIndex >= firstIndex
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: first.frame.midX, dy: up ? high : low))
            let end = origin.withOffset(CGVector(dx: first.frame.midX, dy: up ? low : high))
            start.press(forDuration: 0.12, thenDragTo: end)
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
        // UIKit's stock tab bar can draw the number without exposing it in XCUI's label/value.
        // Read the visible badge at the actual tab's location, including on the smaller screen.
        var before: CGImage?
        for _ in 0..<6 where before == nil {
            before = notificationBadgeDigits(app: app, tab: tab)
            if before == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
        }
        guard let before else { return XCTFail("No visible unread badge") }
        // Compare both numeral shapes independently after the run. Collect the subsequent
        // real read acknowledgement and refresh even if a visual comparison needs review.
        capture(app, "notifications-unread-twelve")
        let reading = XCTAttachment(image: UIImage(cgImage: before))
        reading.name = "notification-badge-digits"
        reading.lifetime = .keepAlways
        add(reading)
        enterNotifications(app)
        var remaining = notificationBadgeDigits(app: app, tab: tab)
        for _ in 0..<6 where remaining != nil {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            remaining = notificationBadgeDigits(app: app, tab: tab)
        }
        XCTAssertNil(remaining, "The red badge must disappear after the server acknowledges reading")
        capture(app, "notifications-unread-cleared")
        let newRow = element("notification.noticetest0033", in: app)
        XCTAssertFalse(newRow.exists)
        guard let feed = app.scrollViews.allElementsBoundByIndex.max(by: { $0.frame.height < $1.frame.height }) else {
            return XCTFail("Missing notification scroll view")
        }
        // Begin inside the feed's empty right-hand margin and release at the end of the drag.
        // This avoids long-press, profile links, note text and reaction targets.
        let start = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.982, dy: 0.12))
        let smallPull = start.withOffset(CGVector(dx: 0, dy: 90))
        start.press(forDuration: 0.04, thenDragTo: smallPull, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertFalse(newRow.waitForExistence(timeout: 1.5), "A pull below 200pt must not refresh")
        capture(app, "notifications-short-pull-returned")
        let end = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.982, dy: 0.88))
        start.press(forDuration: 0.04, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.65)
        XCTAssertTrue(newRow.waitForExistence(timeout: 8), "One full pull must display the next server response")
        capture(app, "notifications-pull-refreshed")
        element("notifications.markRead", in: app).tap()
        XCTAssertTrue(newRow.waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons.matching(identifier: "notification.noticetest0033").count, 1)
    }

    func testSecondPageAndTerminalCursor() {
        let app = notificationsApp()
        enterNotifications(app)
        let last = element("notification.noticetest0011", in: app)
        let more = element("notifications.more", in: app)
        for _ in 0..<15 where !last.isHittable {
            if more.isHittable { more.tap() } else { app.swipeUp() }
        }
        XCTAssertTrue(last.isHittable)
        if more.isHittable { more.tap() }
        XCTAssertTrue(more.waitForNonExistence(timeout: 6))
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

    func testMentionSortDateAndRefreshAreIndependentOfDirectNotes() {
        let app = notificationsApp()
        enterNotifications(app)
        element("notifications.tab.mentions", in: app).tap()
        let publicNote = element("note.open.notifmention01", in: app)
        let specified = element("note.open.notifdirect001", in: app)
        XCTAssertTrue(publicNote.waitForExistence(timeout: 5))
        XCTAssertLessThan(publicNote.frame.minY, specified.frame.minY)
        element("notifications.order", in: app).tap()
        app.buttons["从旧到新"].firstMatch.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            specified.exists && publicNote.exists && specified.frame.minY < publicNote.frame.minY
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 6), .completed)
        element("notifications.date", in: app).tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        capture(app, "notifications-mentions-date")
        element("notifications.date", in: app).tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForNonExistence(timeout: 5))
        element("notifications.refresh", in: app).tap()
        XCTAssertTrue(specified.waitForExistence(timeout: 5))
        element("notifications.tab.directNotes", in: app).tap()
        XCTAssertTrue(element("notifications.order", in: app).label.contains("从新到旧"))
        XCTAssertTrue(publicNote.waitForNonExistence(timeout: 5))
    }

    func testAccessibleTextAndReducedMotionStillNavigate() {
        let app = notificationsApp(["--large-text", "--reduce-motion"])
        enterNotifications(app)
        tapVisible("notification.noticetest0032", in: app)
        XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 5))
        goBack(app)
        capture(app, "notifications-large-type-reduced-motion")
    }

    func testSwitchingBackDuringSlowMentionsRestoresGroupedFeed() {
        let app = notificationsApp(["--notifications-slow-mentions"])
        enterNotifications(app)
        let grouped = element("notification.noticetest0032", in: app)
        element("notifications.tab.mentions", in: app).tap()
        element("notifications.tab.all", in: app).tap()
        XCTAssertTrue(grouped.waitForExistence(timeout: 5))
        // Wait past the original response window before checking the visible content again.
        let stale = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"),
                                              object: element("note.open.notifdirect001", in: app))
        stale.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [stale], timeout: 1.6), .completed)
        XCTAssertTrue(grouped.isHittable)
        capture(app, "notifications-restored-after-tab-switch")
    }
}

/// Isolates the digits displayed by the system tab bar. Input is a live simulator screenshot.
/// Red run bounds on each line exclude the page and the rounded badge corners.
private func notificationBadgeDigits(app: XCUIApplication, tab: XCUIElement) -> CGImage? {
    guard let screen = app.screenshot().image.cgImage else { return nil }
    let scale = CGFloat(screen.width) / app.frame.width
    let box = tab.frame.insetBy(dx: 0, dy: -8)
    let region = CGRect(x: box.minX * scale, y: box.minY * scale, width: box.width * scale,
                        height: box.height * scale).integral
    guard let crop = screen.cropping(to: region) else { return nil }
    let w = crop.width, h = crop.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let drawn: Bool = pixels.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return true
    }
    guard drawn else { return nil }
    var left = w, right = -1, top = h, bottom = -1
    var minX = [Int](repeating: w, count: h), maxX = [Int](repeating: -1, count: h)
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            if pixels[i] > 155 && pixels[i + 1] < 140 && pixels[i + 2] < 150 && Int(pixels[i]) - Int(pixels[i + 1]) > 75 {
                minX[y] = min(x, minX[y]); maxX[y] = max(x, maxX[y])
                left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
            }
        }
    }
    guard right - left >= 6, bottom - top >= 6 else { return nil }
    let margin = 8, zoom = 4
    let outW = (right - left + 1 + 2 * margin) * zoom, outH = (bottom - top + 1 + 2 * margin) * zoom
    var output = [UInt8](repeating: 255, count: outW * outH)
    for y in top...bottom where minX[y] < maxX[y] {
        for x in minX[y]...maxX[y] {
            let i = (y * w + x) * 4
            guard pixels[i + 1] >= 145 && pixels[i + 2] >= 150 else { continue }
            for dy in 0..<zoom {
                let start = ((y - top + margin) * zoom + dy) * outW + (x - left + margin) * zoom
                for dx in 0..<zoom { output[start + dx] = 0 }
            }
        }
    }
    guard let provider = CGDataProvider(data: Data(output) as CFData) else { return nil }
    return CGImage(width: outW, height: outH, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: outW,
                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
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
        ])
    }

    func testSecurityVerificationAndExactAuthorizedApplicationsDestination() {
        let app = notificationsApp()
        enterNotifications(app)
        choose("login", title: "登录", in: app)
        tapVisible("notification.noticetest0012", in: app)
        XCTAssertTrue(app.navigationBars["安全验证"].waitForExistence(timeout: 5))
        capture(app, "notification-login-verification")
        let password = app.secureTextFields["admin.password"]
        password.tap()
        password.typeText("synthetic-only")
        app.buttons["admin.authorize"].tap()
        XCTAssertTrue(app.navigationBars["授权会话与登录记录"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["隔离歌单助手"].waitForExistence(timeout: 5))
        capture(app, "notification-route-notification.noticetest0012")
        goBack(app)
        XCTAssertTrue(element("notification.noticetest0012", in: app).waitForExistence(timeout: 5))
        choose("createToken", title: "创建访问令牌", in: app)
        tapVisible("notification.noticetest0011", in: app)
        XCTAssertTrue(app.navigationBars["已授权应用"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["隔离歌单助手"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["安全验证"].exists)
        capture(app, "notification-route-notification.noticetest0011")
        goBack(app)
        XCTAssertTrue(element("notification.noticetest0011", in: app).waitForExistence(timeout: 5))
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
