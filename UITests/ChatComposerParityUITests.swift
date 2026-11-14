import XCTest

/// Product geometry assertions, not screenshot-only smoke tests. Both simulator
/// sizes execute both disjoint halves through the required presentation matrix.
final class ChatComposerParityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(dark: Bool, flags: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--social-align", "--chat-align", "--four-tabs-drafts"] + (dark ? ["--dark"] : []) + flags
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
        XCTAssertTrue(puboTab(app, "消息").waitForExistence(timeout: 20))
        puboSelectTab(app, "消息")
        return app
    }

    private func open(_ app: XCUIApplication, room: Bool) {
        let row = app.buttons[room ? "conversation.room:socialroom" : "conversation.user:syntheticpeer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable); row.tap()
        XCTAssertTrue(app.textViews[room ? "room.input" : "chat.input"].waitForExistence(timeout: 10))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func revealRetry(_ app: XCUIApplication, prefix: String, retry: XCUIElement) {
        let viewport = app.scrollViews[prefix + ".timeline"]
        let composer = app.descendants(matching: .any).matching(identifier: prefix + ".composer").firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 8))
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        func fullyVisible() -> Bool {
            guard retry.exists else { return false }
            let frame = retry.frame, bounds = viewport.frame
            return frame.minX >= bounds.minX && frame.maxX <= bounds.maxX &&
                frame.minY >= bounds.minY && frame.maxY <= min(bounds.maxY, composer.frame.minY) &&
                puboTouchRectMeetsMinimum(frame)
        }
        for _ in 0..<5 where !fullyVisible() {
            if retry.exists && retry.frame.minY < viewport.frame.minY { viewport.swipeDown() }
            else { viewport.swipeUp() }
        }
        let proof = XCTAttachment(string: "retry=\(retry.frame)\nviewport=\(viewport.frame)\ncomposer=\(composer.frame)\n" + app.debugDescription)
        proof.name = "chat-link-retry-geometry-" + prefix; proof.lifetime = .keepAlways; add(proof)
        XCTAssertTrue(fullyVisible(), "The complete 44pt retry target must be above the composer, not an AX edge hit point")
        XCTAssertTrue(retry.isHittable)
    }

    private func assertComposer(_ app: XCUIApplication, room: Bool, keyboard: Bool) {
        let prefix = room ? "room" : "chat"
        XCTAssertTrue(puboTab(app, "消息").waitForNonExistence(timeout: 5), "Detail must remove the custom tab controls, not just hide Apple's tabBar")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "app.tab.")).count, 0)
        let input = app.textViews[prefix + ".input"]
        XCTAssertTrue(input.isHittable)
        let keyboardView = app.keyboards.firstMatch
        if keyboard { XCTAssertTrue(keyboardView.waitForExistence(timeout: 5)) }
        let bottom = keyboard ? keyboardView.frame.minY : app.frame.maxY
        let ids = room ? ["room.attachments", "room.emoji", "room.send"] : ["chat.attachments", "chat.voice", "chat.emoji", "chat.send"]
        for id in ids {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 5), id)
            XCTAssertTrue(button.isHittable, id + " must not be clipped or covered")
            XCTAssertTrue(puboTouchDimensionMeetsMinimum(button.frame.width), id)
            XCTAssertTrue(puboTouchDimensionMeetsMinimum(button.frame.height), id)
            XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX, id)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX, id)
            XCTAssertLessThanOrEqual(button.frame.maxY, bottom + 0.5, id + " intersects keyboard/screen bottom")
            XCTAssertGreaterThanOrEqual(button.frame.minY, input.frame.maxY - 0.5, id + " overlaps text editor")
        }
        XCTAssertLessThanOrEqual(input.frame.maxY, bottom + 0.5)
    }

    private func assertTimelineHorizontalInsets(_ app: XCUIApplication, room: Bool, stage: String) {
        // Regression for endpoint subtraction at the exact C23 AX coordinates.
        let y = CGFloat(484.3333333333333), maxY = CGFloat(528.3333333333333)
        XCTAssertTrue(puboTouchRectMeetsMinimum(CGRect(x: 16, y: y, width: 44, height: maxY - y)))
        for undersized in [CGFloat(43.999), 43, 42] {
            XCTAssertFalse(puboTouchRectMeetsMinimum(CGRect(x: 16, y: y, width: 44, height: undersized)))
        }
        XCTAssertFalse(puboTouchRectMeetsMinimum(CGRect(x: 16, y: y, width: 44, height: CGFloat.nan)))
        XCTAssertFalse(puboTouchRectMeetsMinimum(CGRect(x: 16, y: 1e20, width: 44, height: 1)))
        XCTAssertFalse(puboTouchRectMeetsMinimum(CGRect(x: 16, y: CGFloat.infinity, width: 44, height: 44)))
        let prefix = room ? "room" : "chat"
        let viewport = app.scrollViews[prefix + ".timeline"]
        let composer = app.descendants(matching: .any).matching(identifier: prefix + ".composer").firstMatch
        let avatars = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix + ".avatar."))
        let tabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix + ".tab."))
        XCTAssertTrue(viewport.waitForExistence(timeout: 6))
        XCTAssertTrue(composer.waitForExistence(timeout: 6))
        // One immutable AX tree per poll: querying each row.frame separately
        // can perform many remote snapshots and exceed the same 8-second gate.
        // Do not reuse a successful snapshot across polls or after navigation.
        var observations: [String] = []
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let started = ProcessInfo.processInfo.systemUptime
            do {
                let tree = try app.snapshot()
                let nodes = puboSnapshotDescendants(tree)
                guard let viewportSnapshot = nodes.first(where: {
                    $0.elementType == .scrollView && $0.identifier == prefix + ".timeline"
                }), let composerSnapshot = nodes.first(where: { $0.identifier == prefix + ".composer" }) else {
                    observations.append("Missing viewport/composer in current snapshot")
                    return false
                }
                let bounds = viewportSnapshot.frame, composerFrame = composerSnapshot.frame
                let avatarSnapshots = nodes.filter {
                    $0.elementType == .button && $0.identifier.hasPrefix(prefix + ".avatar.")
                }
                // Filter only by vertical visibility. A clipped or undersized
                // horizontal target must remain a candidate and fail below.
                let frames = avatarSnapshots.map { $0.frame }.filter { frame in
                    frame.minY >= bounds.minY && frame.maxY <= min(bounds.maxY, composerFrame.minY)
                }
                let valid = !frames.isEmpty && frames.allSatisfy { frame in
                    puboTouchRectMeetsMinimum(frame) &&
                    frame.minX >= bounds.minX && frame.maxX <= bounds.maxX &&
                    abs(frame.minX - bounds.minX - 16) <= 1
                }
                observations.append("duration=\(ProcessInfo.processInfo.systemUptime - started) viewport=\(bounds) composer=\(composerFrame) avatars=\(avatarSnapshots.map { "\($0.identifier)=\($0.frame)" }) valid=\(valid)")
                return valid
            } catch {
                observations.append("duration=\(ProcessInfo.processInfo.systemUptime - started) snapshotError=\(error)")
                return false
            }
        }, object: nil)
        let result = XCTWaiter.wait(for: [settled], timeout: 8)
        let rows = avatars.allElementsBoundByIndex.map { "\($0.identifier)=\($0.frame)" }.joined(separator: "\n")
        let tabFrames = tabs.allElementsBoundByIndex.map { "\($0.identifier)=\($0.frame)" }.joined(separator: "\n")
        let proof = XCTAttachment(string: "stage=\(stage)\nobservations=\(observations.joined(separator: "\n"))\nviewport=\(viewport.frame)\ncomposer=\(composer.frame)\ntabs:\n\(tabFrames)\navatars:\n\(rows)\n" + app.debugDescription)
        proof.name = "chat-horizontal-insets-" + prefix + "-" + stage
        proof.lifetime = .keepAlways; add(proof)
        XCTAssertEqual(result, .completed, "At least one complete fixture avatar must be visible, with real viewport-relative 16pt inset; never scroll just to satisfy this gate")
    }

    private func backToHome(_ app: XCUIApplication) {
        // Actual navigation, never a test-only path reset or tab switch.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.isHittable); back.tap()
        XCTAssertTrue(puboTab(app, "消息").waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "app.tab.")).count, 4)
        for title in ["消息", "好友", "世界圈", "我的"] { XCTAssertTrue(puboTab(app, title).isHittable) }
    }

    private func layoutAndReturn(room: Bool) {
        for dark in [false, true] {
            let app = launch(dark: dark), theme = dark ? "dark" : "light", kind = room ? "room" : "private"
            open(app, room: room); assertComposer(app, room: room, keyboard: false)
            assertTimelineHorizontalInsets(app, room: room, stage: "ordinary-" + theme)
            capture(app, "chat-composer-" + kind + "-" + theme)
            // Exercise the real attachment menu and a cancellable picker. Native
            // camera/microphone permissions are intentionally not synthesized.
            app.buttons[room ? "room.attachments" : "chat.attachments"].tap()
            let drive = app.buttons[room ? "从网盘选择" : "从网盘导入"]
            XCTAssertTrue(drive.waitForExistence(timeout: 5)); drive.tap()
            let cancel = app.buttons["取消"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
            assertComposer(app, room: room, keyboard: false)
            backToHome(app); capture(app, "chat-composer-return-" + kind + "-" + theme)
            // Repeat entry to catch stale visibility registrations.
            open(app, room: room); assertComposer(app, room: room, keyboard: false)
            backToHome(app); app.terminate()
        }
    }

    private func keyboardAndDraft(room: Bool) {
        for dark in [false, true] {
            let app = launch(dark: dark), theme = dark ? "dark" : "light", kind = room ? "room" : "private"
            let prefix = room ? "room" : "chat", draft = "草稿保留 " + kind
            open(app, room: room)
            let input = app.textViews[prefix + ".input"]
            input.tap(); input.typeText(draft)
            assertComposer(app, room: room, keyboard: true)
            XCTAssertTrue(app.buttons[prefix + ".send"].isEnabled)
            assertTimelineHorizontalInsets(app, room: room, stage: "keyboard-" + theme)
            capture(app, "chat-composer-keyboard-" + kind + "-" + theme)
            backToHome(app); open(app, room: room)
            XCTAssertEqual(app.textViews[prefix + ".input"].value as? String, draft)
            assertComposer(app, room: room, keyboard: false)
            assertTimelineHorizontalInsets(app, room: room, stage: "draft-restored-" + theme)
            capture(app, "chat-composer-draft-restored-" + kind + "-" + theme)
            app.terminate()
        }
    }

    func testInitialLoadingAndEmptyConversationStates() throws {
        for room in [false, true] {
            let gate = try ChatLoadingTestGate(room: room)
            defer { gate.close() }
            let app = launch(dark: false, flags: ["--chat-load-gate", "--chat-load-empty"], environment: gate.environment)
            defer { app.terminate() }
            let prefix = room ? "room" : "chat"
            open(app, room: room)
            let loading = app.descendants(matching: .any).matching(identifier: prefix + ".loading").firstMatch
            XCTAssertTrue(loading.waitForExistence(timeout: 3)); capture(app, "chat-state-loading-" + prefix)
            try gate.release()
            let empty = app.descendants(matching: .any).matching(identifier: prefix + ".empty").firstMatch
            XCTAssertTrue(empty.waitForExistence(timeout: 15)); XCTAssertFalse(loading.exists)
            XCTAssertFalse(app.buttons[prefix + ".retry"].exists)
            assertComposer(app, room: room, keyboard: false); capture(app, "chat-state-empty-" + prefix)
            app.terminate()
        }
    }

    func testInitialFailureHasExplicitRetryAndRecovers() {
        for room in [false, true] {
            let app = launch(dark: false, flags: ["--chat-load-delay", "--chat-load-fail-once"])
            let prefix = room ? "room" : "chat"
            open(app, room: room)
            let retry = app.buttons[prefix + ".retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: 15)); XCTAssertTrue(retry.isHittable)
            XCTAssertTrue(app.staticTexts[prefix + ".loadError"].exists)
            capture(app, "chat-state-failed-" + prefix)
            retry.tap()
            XCTAssertTrue(retry.waitForNonExistence(timeout: 15))
            let expected = room ? "欢迎来到音乐交流群。" : "你好，欢迎来到 PUBO。"
            // C17's actual AX tree exposes the group body through its established
            // bubble identifier; the ancestor replaces the inner UIKit identifier.
            let messageID = room ? "room.bubble.room0001" : "chat.text.private0001"
            let message = app.descendants(matching: .any).matching(identifier: messageID).firstMatch
            XCTAssertTrue(message.waitForExistence(timeout: 15))
            XCTAssertTrue(message.label.contains(expected) || (message.value as? String)?.contains(expected) == true)
            assertComposer(app, room: room, keyboard: false); capture(app, "chat-state-recovered-" + prefix)
            app.terminate()
        }
    }

    func testRoomSenderNamesRespectSyncedPreference() {
        for enabled in [false, true] {
            let app = launch(dark: false, flags: enabled ? ["--chat-sender-names"] : [])
            open(app, room: true)
            let name = app.staticTexts["room.sender.room0001"]
            if enabled {
                for _ in 0..<4 where !name.isHittable { app.swipeDown() }
                XCTAssertTrue(name.waitForExistence(timeout: 8))
                XCTAssertEqual(name.label, "测试朋友")
            } else { XCTAssertFalse(name.exists) }
            capture(app, enabled ? "chat-room-sender-name-on" : "chat-room-sender-name-off")
            app.terminate()
        }
    }

    func testLinkPreviewFailurePreservesDestinationAndRetries() {
        for room in [false, true] {
            let app = launch(dark: false, flags: ["--chat-preview-failure"])
            let prefix = room ? "room" : "chat", cardID = (room ? "room" : "chat") + ".links.zzchat-link-fixture.0"
            open(app, room: room)
            let card = app.buttons[cardID], retry = app.buttons[cardID + ".retry"]
            for _ in 0..<5 where !card.isHittable { app.swipeUp() }
            XCTAssertTrue(card.waitForExistence(timeout: 8))
            XCTAssertTrue(retry.waitForExistence(timeout: 8))
            revealRetry(app, prefix: prefix, retry: retry)
            XCTAssertTrue(card.label.contains("https://example.com/pubo-chat-fixture"))
            XCTAssertTrue(card.label.contains("暂时无法预览"))
            capture(app, "chat-link-fallback-" + prefix)
            retry.tap()
            XCTAssertTrue(retry.waitForNonExistence(timeout: 8))
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "PUBO 合成链接预览"), object: card)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 8), .completed)
            XCTAssertTrue(card.label.contains("这是隔离测试中的链接摘要"))
            XCTAssertTrue(card.isHittable)
            capture(app, "chat-link-retried-" + prefix)
            // Do not open an external site just to assert this synthetic card.
            app.terminate()
        }
    }

    func testPrivateComposerToolsAndBackRestoreBothThemes() { layoutAndReturn(room: false) }
    func testRoomComposerToolsAndBackRestoreBothThemes() { layoutAndReturn(room: true) }
    func testPrivateKeyboardAndDraftSurviveBackBothThemes() { keyboardAndDraft(room: false) }
    func testRoomKeyboardAndDraftSurviveBackBothThemes() { keyboardAndDraft(room: true) }
}
