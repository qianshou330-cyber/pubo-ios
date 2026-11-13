import XCTest

/// Candidate-only coverage. FixtureTransport owns all data; no production accounts,
/// real camera, APNs entitlement or signed-install claim is made by these tests.
final class FourTabNavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reduce-motion"] + flags
        app.launch()
        XCTAssertTrue(tabButton(app, "消息").waitForExistence(timeout: 20))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "four-tabs-" + name; shot.lifetime = .keepAlways; add(shot)
    }
    private func waitForText(_ app: XCUIApplication, _ id: String, _ expected: String) {
        // Each poll resolves a fresh actual editor. No retyping or partial value
        // acceptance; attach timing only after the single bounded wait.
        let started = ProcessInfo.processInfo.systemUptime
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.textViews[id].value as? String == expected
        }, object: nil)
        let result = XCTWaiter.wait(for: [complete], timeout: 10)
        let ended = ProcessInfo.processInfo.systemUptime
        let actual = app.textViews[id].value as? String ?? "<nil>"
        let evidence = XCTAttachment(string: "start=\(started)\nend=\(ended)\nduration=\(ended-started)\nactualLength=\(actual.count)\nactual=\(actual)")
        evidence.name = "four-tabs-input-completion"; evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(actual, expected)
    }
    private func assertChatBadge(_ app: XCUIApplication, count: String) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (self.tabButton(app, "消息").value as? String) == count + " 条未读聊天"
        }, object: nil)
        // Unread is asynchronous. Wait for real model-backed accessibility data,
        // then independently read rendered pixels once, never supply OCR an expected digit.
        let result = XCTWaiter.wait(for: [ready], timeout: 10)
        let messages = tabButton(app, "消息")
        let tree = XCTAttachment(string: "label=\(messages.label)\nvalue=\(String(describing: messages.value))\n\(app.debugDescription)")
        tree.name = "four-tabs-chat-badge-accessibility"; tree.lifetime = .keepAlways; add(tree)
        capture(app, "chat-badge-expected-" + count)
        XCTAssertEqual(result, .completed)
        let reading = readTabBadge(app: app, tab: messages)
        XCTContext.runActivity(named: "Independent rendered chat badge OCR") {
            reading.attach(to: $0, name: "four-tabs-chat-badge")
        }
        XCTAssertEqual(reading.recognizedText, count, reading.failureReason ?? reading.readings.joined(separator: "\n"))
    }
    private func tabButton(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let ids = ["消息": "messages", "好友": "friends", "世界圈": "world", "我的": "me"]
        return app.buttons["app.tab." + ids[title]!]
    }
    private func assertBottomBarGeometry(_ app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let bar = element(app, "app.tabBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        let frame = bar.frame
        XCTAssertEqual(frame.minX, window.minX, accuracy: 1)
        XCTAssertEqual(frame.width, window.width, accuracy: 1)
        let expectedBottom: CGFloat = window.height < 750 ? 0 : 34
        XCTAssertEqual(window.maxY - frame.maxY, expectedBottom, accuracy: 2)
        for (index, title) in ["消息", "好友", "世界圈", "我的"].enumerated() {
            let button = tabButton(app, title)
            XCTAssertTrue(button.isHittable, title)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertEqual(button.frame.width, window.width / 4, accuracy: 1)
            XCTAssertEqual(button.frame.midX, window.minX + (CGFloat(index) + 0.5) * window.width / 4, accuracy: 1)
            XCTAssertLessThanOrEqual(button.frame.maxY, frame.maxY + 1)
        }
        let evidence = XCTAttachment(string: "window=\(window)\nbar=\(frame)\nexpectedHomeIndicatorInset=\(expectedBottom)\n\(app.debugDescription)")
        evidence.name = "four-tabs-bottom-safe-area-geometry"; evidence.lifetime = .keepAlways; add(evidence)
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func tap(_ app: XCUIApplication, _ id: String) {
        let control = element(app, id)
        _ = control.waitForExistence(timeout: 3)
        for _ in 0..<8 where !control.isHittable { app.swipeUp() }
        XCTAssertTrue(control.waitForExistence(timeout: 8), id)
        XCTAssertTrue(control.isHittable, id); control.tap()
    }
    private func tab(_ app: XCUIApplication, _ title: String) {
        let control = tabButton(app, title)
        XCTAssertTrue(control.waitForExistence(timeout: 8)); control.tap()
        XCTAssertTrue(control.isSelected)
    }
    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.firstMatch.tap() }
    private func openRequests(_ app: XCUIApplication) {
        tab(app, "好友"); tap(app, "friends.requests")
        XCTAssertTrue(app.segmentedControls["followRequests.direction"].waitForExistence(timeout: 8))
    }

    func testFourRootsAndExclusiveComposerInBothThemes() {
        for dark in [false, true] {
            let app = launch(["--social-align", "--timeline-align", "--gif-preview"] + (dark ? ["--dark"] : []))
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "app.tab.")).count, 4)
            XCTAssertTrue(tabButton(app, "消息").isSelected)
            for title in ["消息", "好友", "世界圈", "我的"] {
                tab(app, title)
                if title == "世界圈" {
                    XCTAssertTrue(app.buttons["home.compose"].waitForExistence(timeout: 8))
                    XCTAssertTrue(app.buttons["world.recommended"].exists)
                    XCTAssertTrue(app.buttons["world.following"].exists)
                    XCTAssertFalse(app.buttons["附近"].exists)
                } else { XCTAssertFalse(app.buttons["home.compose"].exists) }
                assertBottomBarGeometry(app)
                capture(app, title + (dark ? "-dark" : "-light"))
            }
            app.terminate()
        }
    }

    func testGuestLandingStillLoadsPublicPanels() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--logged-out", "--reduce-motion"]
        app.launch()
        XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 15))
        XCTAssertFalse(element(app, "app.tabBar").exists)
        let chart = app.buttons["home.chartDetail"]
        for _ in 0..<8 where !chart.isHittable { app.swipeUp() }
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        XCTAssertTrue(chart.isHittable)
        capture(app, "guest-public-panels-preserved")
        app.terminate()
    }

    func testMessageMenuSearchAndKeyboardReturn() {
        let app = launch()
        tap(app, "messages.add")
        XCTAssertTrue(app.buttons["messages.scan"].exists)
        XCTAssertTrue(app.buttons["messages.addUsername"].exists)
        XCTAssertFalse(app.buttons["创建群聊"].exists)
        XCTAssertFalse(app.buttons["建群"].exists)
        capture(app, "message-plus-menu")
        tap(app, "messages.addUsername")
        let field = app.textFields["addFriend.username"]
        XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); field.typeText("friend")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "app.tabBar").waitForNonExistence(timeout: 5))
        capture(app, "username-keyboard-no-floating-bar")
        tap(app, "addFriend.search")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        assertBottomBarGeometry(app)
        let result = element(app, "addFriend.result.syntheticpeer")
        XCTAssertTrue(result.waitForExistence(timeout: 8)); capture(app, "username-search-results")
        result.tap()
        XCTAssertTrue(app.navigationBars["个人主页"].waitForExistence(timeout: 8))
        // Merely searching/opening a profile must not submit a follow request.
        XCTAssertTrue(app.buttons["profile.follow"].waitForExistence(timeout: 8))
        back(app); XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.terminate()
    }

    func testScannerSyntheticFallbackDoesNotRequestCamera() {
        let app = launch()
        tap(app, "messages.add"); tap(app, "messages.scan")
        XCTAssertTrue(app.staticTexts["演示测试不启用相机，请使用用户名搜索。"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture(app, "scanner-simulator-fallback-not-real-camera")
        tap(app, "scanner.username")
        XCTAssertTrue(app.textFields["addFriend.username"].waitForExistence(timeout: 8))
        app.terminate()
    }

    func testChatAndFriendStacksSurviveTabSwitches() {
        let app = launch(["--social-align"])
        let friend = element(app, "conversation.user:syntheticpeer")
        XCTAssertTrue(friend.waitForExistence(timeout: 10)); friend.tap()
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 8))
        tab(app, "好友"); tap(app, "friends.contacts")
        XCTAssertTrue(app.navigationBars["联系人"].waitForExistence(timeout: 8))
        tab(app, "消息")
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 8))
        tab(app, "好友")
        XCTAssertTrue(app.navigationBars["联系人"].waitForExistence(timeout: 8))
        capture(app, "independent-friend-back-stack")
        back(app); XCTAssertTrue(app.buttons["friends.requests"].waitForExistence(timeout: 8))
        tap(app, "friends.rooms")
        XCTAssertTrue(app.navigationBars["群聊"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["创建群聊"].exists)
        XCTAssertTrue(app.staticTexts["PUBO 音乐交流"].waitForExistence(timeout: 8))
        capture(app, "existing-rooms-without-create")
        tab(app, "消息"); back(app)
        XCTAssertTrue(app.buttons["messages.add"].waitForExistence(timeout: 8))
        app.terminate()
    }

    func testWorldComposerKeyboardAndCloseWithoutSending() {
        let app = launch(["--four-tabs-drafts"])
        tab(app, "世界圈"); tap(app, "home.compose")
        let editor = app.textViews["compose.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8)); editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("Unsent four tab draft")
        waitForText(app, "compose.text", "Unsent four tab draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        capture(app, "compose-keyboard")
        tap(app, "compose.close")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["home.compose"].waitForExistence(timeout: 8))
        tab(app, "消息"); XCTAssertFalse(app.buttons["home.compose"].exists)
        tab(app, "世界圈"); tap(app, "home.compose")
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertEqual(editor.value as? String, "Unsent four tab draft")
        capture(app, "compose-restored-after-tab-switch")
        app.terminate()
    }

    func testMigratedDiscoveryAndAccountEntriesRemainReachable() {
        let app = launch()
        tab(app, "世界圈"); tap(app, "world.more")
        XCTAssertTrue(app.buttons["全部公告"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.chartDetail"].waitForExistence(timeout: 10))
        for title in ["频道", "图库"] {
            let entry = app.buttons[title]
            for _ in 0..<8 where !entry.isHittable { app.swipeUp() }
            XCTAssertTrue(entry.isHittable, title)
        }
        capture(app, "world-discovery")
        tab(app, "我的")
        let entries = [("me.profile", "我的主页"), ("me.favorites", "我的收藏"), ("me.drive", "网盘"), ("me.notifications", "通知")]
        for (id, title) in entries {
            tap(app, id)
            XCTAssertTrue(app.navigationBars.containing(NSPredicate(format: "identifier CONTAINS %@", title)).firstMatch.waitForExistence(timeout: 8), title)
            capture(app, "migrated-" + id)
            back(app)
        }
        tap(app, "me.accounts"); XCTAssertTrue(app.buttons["accounts.select.syntheticself"].waitForExistence(timeout: 8))
        capture(app, "accounts-entry"); app.terminate()
    }

    func testFollowRequestPendingCancelAndLoadingStayTruthful() {
        let app = launch(["--follow-requests-preview", "--four-tabs-follow-hold"])
        openRequests(app)
        let reject = app.buttons["followRequests.reject.received-031"]
        XCTAssertTrue(reject.waitForExistence(timeout: 10))
        reject.tap(); tap(app, "followRequests.keep"); XCTAssertTrue(reject.exists)
        app.segmentedControls["followRequests.direction"].buttons["已发送的申请"].tap()
        XCTAssertTrue(element(app, "followRequests.loading").waitForExistence(timeout: 5))
        capture(app, "follow-request-loading")
        app.segmentedControls["followRequests.direction"].buttons["收到的申请"].tap()
        XCTAssertTrue(reject.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["followRequests.cancel.sent-001"].exists)
        capture(app, "follow-request-real-semantics")
        app.terminate()
    }

    func testFriendsEmptyAndFailedReadCanRetry() {
        var app = launch(["--follow-list-preview", "--follow-list-empty"])
        tab(app, "好友")
        XCTAssertTrue(element(app, "friends.empty").waitForExistence(timeout: 10))
        capture(app, "friends-empty"); app.terminate()
        app = launch(["--follow-list-preview", "--follow-list-failure-once"])
        tab(app, "好友")
        let retry = app.buttons["friends.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10)); capture(app, "friends-read-failure")
        tap(app, "friends.retry")
        XCTAssertTrue(app.staticTexts["关系用户 031"].waitForExistence(timeout: 10))
        XCTAssertFalse(retry.exists)
        capture(app, "friends-retry-recovered"); app.terminate()
        app = launch(["--four-tabs-friends-hold"])
        tab(app, "好友")
        XCTAssertTrue(element(app, "friends.loading").waitForExistence(timeout: 5))
        capture(app, "friends-loading-request-pending")
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["测试朋友"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "friends.loading").waitForNonExistence(timeout: 5))
        capture(app, "friends-loading-released-by-real-refresh"); app.terminate()
        app = launch(["--four-tabs-messages-empty"])
        XCTAssertTrue(element(app, "messages.empty").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["messages.retry"].exists)
        capture(app, "messages-empty"); app.terminate()
        app = launch(["--four-tabs-messages-error"])
        XCTAssertTrue(app.buttons["messages.retry"].waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "messages.empty").exists)
        capture(app, "messages-failure-not-empty"); app.terminate()
        for (flag, resultID) in [("--four-tabs-search-empty", "addFriend.empty"), ("--four-tabs-search-denied", "addFriend.retry")] {
            app = launch([flag])
            tap(app, "messages.add"); tap(app, "messages.addUsername")
            let field = app.textFields["addFriend.username"]
            XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); field.typeText("unknown")
            tap(app, "addFriend.search")
            XCTAssertTrue(element(app, resultID).waitForExistence(timeout: 8))
            if resultID == "addFriend.retry" { XCTAssertFalse(element(app, "addFriend.empty").exists) }
            capture(app, flag); app.terminate()
        }
    }

    func testWorldLoadingFailureAndLargeTextRemainNavigable() {
        var app = launch(["--skeleton-loading"])
        tab(app, "世界圈")
        XCTAssertTrue(element(app, "loading.post").waitForExistence(timeout: 5))
        capture(app, "world-loading"); app.terminate()
        app = launch(["--network-error", "--large-text"])
        tab(app, "世界圈")
        XCTAssertTrue(element(app, "timeline.refreshRetry").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.compose"].isHittable)
        capture(app, "world-error-large-text")
        tab(app, "好友"); XCTAssertTrue(app.buttons["friends.add"].waitForExistence(timeout: 8))
        tab(app, "消息"); XCTAssertTrue(app.buttons["messages.add"].waitForExistence(timeout: 8))
        app.terminate()
    }

    func testOpeningNotificationsDoesNotClearChatBadge() {
        let app = launch(["--parity-preview"])
        assertChatBadge(app, count: "2")
        tab(app, "我的"); tap(app, "me.notifications")
        XCTAssertTrue(app.buttons["notifications.filter"].waitForExistence(timeout: 10))
        assertChatBadge(app, count: "2")
        capture(app, "notification-chat-badge-isolation")
        tab(app, "消息"); assertChatBadge(app, count: "2")
        app.terminate()
    }

    func testAccountSwitchClearsPreviousNavigationStacks() {
        let app = launch(["--multi-account-preview", "--social-align", "--four-tabs-drafts"])
        let friend = element(app, "conversation.user:syntheticpeer")
        XCTAssertTrue(friend.waitForExistence(timeout: 10)); friend.tap()
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 8))
        tab(app, "好友"); tap(app, "friends.contacts")
        tab(app, "世界圈"); tap(app, "home.compose")
        let editor = app.textViews["compose.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8)); editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("Account A private draft")
        waitForText(app, "compose.text", "Account A private draft")
        tap(app, "compose.close"); tap(app, "world.more")
        tab(app, "我的"); tap(app, "me.accounts"); tap(app, "accounts.select.syntheticsecond")
        tab(app, "我的")
        XCTAssertTrue(app.staticTexts["第二个测试账号"].waitForExistence(timeout: 10))
        tab(app, "消息"); XCTAssertTrue(app.buttons["messages.add"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textViews["chat.input"].exists)
        tab(app, "好友"); XCTAssertTrue(app.buttons["friends.requests"].waitForExistence(timeout: 8))
        tab(app, "世界圈"); XCTAssertTrue(app.buttons["home.compose"].waitForExistence(timeout: 8))
        capture(app, "account-switch-cleared-stacks")
        tap(app, "home.compose")
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertFalse((editor.value as? String ?? "").contains("Account A private draft"))
        tap(app, "compose.close")
        tab(app, "我的"); tap(app, "me.accounts"); tap(app, "accounts.select.syntheticself")
        tab(app, "世界圈"); tap(app, "home.compose")
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertEqual(editor.value as? String, "Account A private draft")
        capture(app, "account-drafts-isolated-and-restored")
        app.terminate()
    }

    func testSyntheticPushRoutesUseCorrectTabNotGlobalSheet() {
        for (flag, title, target) in [("--four-tabs-push-chat", "消息", "chat.input"),
                                       ("--four-tabs-push-note", "世界圈", "帖子"),
                                       ("--four-tabs-push-follow", "好友", "followRequests.direction")] {
            let app = launch([flag, "--follow-requests-preview"])
            let destination = target == "帖子" ? app.navigationBars["帖子"] : element(app, target)
            XCTAssertTrue(destination.waitForExistence(timeout: 12), flag)
            XCTAssertTrue(tabButton(app, title).isSelected)
            XCTAssertEqual(app.sheets.count, 0)
            capture(app, "synthetic-route-" + title)
            tab(app, "我的"); tab(app, title)
            XCTAssertTrue(destination.waitForExistence(timeout: 8))
            app.terminate()
        }
        let cold = launch(["--four-tabs-push-chat", "--four-tabs-push-cold"])
        XCTAssertTrue(cold.textViews["chat.input"].waitForExistence(timeout: 12))
        XCTAssertTrue(tabButton(cold, "消息").isSelected)
        XCTAssertEqual(cold.sheets.count, 0)
        capture(cold, "synthetic-cold-launch-notice-retained"); cold.terminate()
        let mismatch = launch(["--four-tabs-push-note", "--four-tabs-push-mismatch"])
        XCTAssertTrue(mismatch.buttons["messages.add"].waitForExistence(timeout: 10))
        XCTAssertTrue(tabButton(mismatch, "消息").isSelected)
        tab(mismatch, "世界圈")
        XCTAssertTrue(mismatch.buttons["home.compose"].waitForExistence(timeout: 8))
        XCTAssertFalse(mismatch.navigationBars["帖子"].exists)
        capture(mismatch, "reject-other-account-push"); mismatch.terminate()
    }
}
