import XCTest

final class LocalTimelineUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--timeline-align", "--gif-preview"] + flags; app.launch()
        puboSelectTab(app, "世界圈")
        XCTAssertTrue(app.buttons["world.more"].waitForExistence(timeout: 15)); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
    private func find(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func animationPlayer(_ app: XCUIApplication) -> XCUIElement {
        // SwiftUI may expose both a media container and its UIKit animation child.
        // Query the actual decoder's value, never the container's empty value.
        let player = app.descendants(matching: .any).matching(NSPredicate(format:
            "(identifier == %@ OR identifier == %@) AND value BEGINSWITH %@",
            "media.animation.timelinegif", "media.open.timelinegif", "frame=")).firstMatch
        if !player.waitForExistence(timeout: 12) {
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "animation-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
            XCTFail("The real animated image must expose its decoder frame state")
        }
        return player
    }
    private func reveal(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let item = find(app, id)
        let scroll = app.scrollViews["timeline.scroll"]
        for _ in 0..<32 {
            let upper = max(110, app.buttons["home.more"].frame.maxY + 12)
            let lower = app.descendants(matching: .any).matching(identifier: "app.tabBar").firstMatch.frame.minY - 16
            if item.exists && item.isHittable && item.frame.midY > upper && item.frame.midY < lower { return item }
            let reverse = item.exists && item.frame.midY <= upper
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: reverse ? 0.40 : 0.72))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: reverse ? 0.72 : 0.40))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return item
    }
    func testFirstLocalAndFourTabsInBothThemes() {
        for dark in [false, true] {
            let app = launch(dark ? ["--dark"] : [])
            XCTAssertTrue(app.buttons["world.recommended"].isSelected)
            XCTAssertTrue(find(app,"note.open.at4tltest0025").waitForExistence(timeout: 10))
            for title in ["消息", "好友", "世界圈", "我的"] { XCTAssertTrue(puboTab(app, title).exists) }
            capture(app, dark ? "local-home-dark" : "local-home-light")
            Thread.sleep(forTimeInterval: 7) // Record uninterrupted real feed media animation; marquee is in discovery.
            app.buttons["home.more"].tap(); XCTAssertTrue(app.buttons["仅限媒体"].exists); capture(app, dark ? "local-filters-dark" : "local-filters-light")
            app.terminate()
        }
    }
    func testMediaFilterAndSensitiveReveal() {
        let app = launch(); app.buttons["home.more"].tap(); app.buttons["仅限媒体"].tap()
        let hidden = reveal(app,"media.reveal.timelinesensitive"); XCTAssertTrue(hidden.exists)
        XCTAssertFalse(find(app,"media.open.timelinesensitive").exists)
        capture(app,"local-sensitive-hidden"); hidden.tap()
        XCTAssertTrue(find(app,"media.open.timelinesensitive").waitForExistence(timeout: 8)); capture(app,"local-sensitive-revealed")
        app.terminate()
    }
    func testMultiImageGridUsesH5ArrangementAndSeparateTargets() {
        for count in [2, 3, 4] {
            let app = launch(["--timeline-grid=\(count)"])
            let first = reveal(app,"media.open.timelineimage1")
            let second = find(app,"media.open.timelineimage2")
            XCTAssertTrue(first.isHittable); XCTAssertTrue(second.isHittable)
            XCTAssertLessThan(first.frame.minX, second.frame.minX)
            if count == 3 {
                let third = find(app,"media.open.timelineimage3")
                XCTAssertGreaterThan(first.frame.height, second.frame.height * 1.8)
                XCTAssertEqual(second.frame.minX, third.frame.minX, accuracy: 2)
                XCTAssertGreaterThan(third.frame.minY, second.frame.minY)
            } else if count == 4 {
                let fourth = find(app,"media.open.timelineimage4")
                XCTAssertEqual(second.frame.minX, fourth.frame.minX, accuracy: 2)
                XCTAssertGreaterThan(fourth.frame.minY, second.frame.minY)
            }
            capture(app,"local-media-grid-\(count)")
            second.tap(); XCTAssertTrue(app.buttons["attachment.saveFile"].waitForExistence(timeout: 10))
            app.buttons["关闭"].tap(); app.terminate()
        }
    }
    func testPublicGIFAutomaticallyMovesWithoutControls() {
        let app = launch(); let image = reveal(app,"media.open.timelinegif"); XCTAssertTrue(image.exists)
        let player = animationPlayer(app)
        var frames = Set<String>(); let deadline = Date().addingTimeInterval(3)
        while Date() < deadline { frames.insert(player.value as? String ?? ""); Thread.sleep(forTimeInterval: 0.11) }
        XCTAssertGreaterThan(frames.count,1); XCTAssertFalse(app.buttons["暂停"].exists); capture(app,"local-gif-autoplay")
        app.terminate()
    }
    func testPublicAPNGAndWebPAnimateAndFiniteGIFKeepsLoopCount() {
        for format in ["apng", "webp", "finite"] {
            let app = launch(["--timeline-format=" + format])
            _ = reveal(app,"media.open.timelinegif")
            let player = animationPlayer(app)
            let deadline = Date().addingTimeInterval(format == "finite" ? 12 : 3)
            var frames = Set<String>(); var completed = false
            while Date() < deadline {
                let value = player.value as? String ?? ""
                frames.insert(value)
                if format == "finite" && value.contains("loops=2;") && value.contains("playing=false") { completed = true; break }
                Thread.sleep(forTimeInterval: 0.11)
            }
            if format == "finite" {
                XCTAssertTrue(completed); let stopped = player.value as? String
                Thread.sleep(forTimeInterval: 1.2); XCTAssertEqual(player.value as? String, stopped)
            } else { XCTAssertGreaterThan(frames.count,1) }
            capture(app,"local-animation-" + format); app.terminate()
        }
    }
    func testReactionToggleAndReadback() {
        let app = launch(); let reaction = app.buttons.matching(identifier: "note.reaction.at4tltest0025.❤️").firstMatch
        XCTAssertTrue(reaction.waitForExistence(timeout: 10)); reaction.tap()
        XCTAssertTrue(app.buttons["取消反应"].waitForExistence(timeout: 8)); capture(app,"local-reaction-selected")
        let custom = app.buttons.matching(identifier: "note.reaction.at4tltest0025.:a2o_lite_aijing1:").firstMatch
        custom.tap(); let confirmation = app.buttons.matching(identifier: "note.confirmReaction.at4tltest0025").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); confirmation.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "已选择"), object: custom)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        XCTAssertEqual(reaction.value as? String, "未选择"); capture(app,"local-reaction-replaced")
        custom.tap(); XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); confirmation.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "未选择"), object: custom)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
        capture(app,"local-reaction-cancelled"); app.terminate()
    }
    func testNewPostsQueueAndReturnToTop() {
        let app = launch(["--timeline-events"])
        XCTAssertTrue(reveal(app,"note.open.at4tltest0021").isHittable)
        app.buttons["home.more"].tap(); app.buttons["测试新帖"].tap()
        XCTAssertTrue(app.buttons["timeline.newPosts"].waitForExistence(timeout: 5)); capture(app,"local-new-posts-queued")
        app.buttons["timeline.newPosts"].tap()
        XCTAssertTrue(find(app,"note.open.zznewtimeline0001").waitForExistence(timeout: 8)); capture(app,"local-new-posts-shown"); app.terminate()
    }
    func testDeletionClearsReferencedBody() {
        let app = launch(["--timeline-events"])
        XCTAssertTrue(reveal(app,"note.open.at4tltest0021").isHittable)
        app.buttons["home.more"].tap(); app.buttons["测试删除原帖"].tap()
        XCTAssertTrue(find(app,"note.context.unavailable").waitForExistence(timeout: 8)); capture(app,"local-deleted-reference"); app.terminate()
    }
    func testOlderPagesRemainReachable() {
        let app = launch()
        let oldest = reveal(app,"note.open.at4tltest0001"); XCTAssertTrue(oldest.exists)
        capture(app,"local-history-pagination"); oldest.tap()
        XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 8)); app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(find(app,"note.open.at4tltest0001").isHittable, "Returning from a historical post must preserve the loaded pages and reading position")
        app.terminate()
    }
    func testBodyAuthorAndMediaOpenOnlyTheirOwnDestinations() {
        let app = launch()
        let body = find(app,"note.open.at4tltest0025"); XCTAssertTrue(body.waitForExistence(timeout: 10)); body.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
        XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 8)); capture(app,"local-body-destination")
        app.navigationBars.buttons.firstMatch.tap()
        let author = app.buttons.matching(identifier: "note.author.at4tltest0025").firstMatch; XCTAssertTrue(author.waitForExistence(timeout: 8)); author.tap()
        XCTAssertTrue(app.navigationBars["个人主页"].waitForExistence(timeout: 8)); capture(app,"local-author-destination")
        app.navigationBars.buttons.firstMatch.tap()
        let media = reveal(app,"media.open.timelinegif"); XCTAssertTrue(media.isHittable); media.tap()
        XCTAssertTrue(app.buttons["attachment.saveFile"].waitForExistence(timeout: 10)); capture(app,"local-media-destination")
        app.buttons["关闭"].tap(); XCTAssertTrue(app.buttons["world.recommended"].exists); app.terminate()
    }
    func testReducedMotionAndLargeTextKeepFiltersReachable() {
        let app = launch(["--reduce-motion", "--large-text"])
        app.buttons["home.more"].tap(); XCTAssertTrue(app.buttons["显示转帖"].exists)
        capture(app,"local-large-text-filters"); app.terminate()
    }
    func testSavedChoiceMigratesAndStaysIsolatedAcrossAccounts() {
        let flags = ["--timeline-persistence", "--multi-account-preview"]
        var app = launch(flags + ["--reset-timeline-preferences", "--legacy-timeline-home"])
        XCTAssertTrue(app.buttons["world.following"].isSelected)
        app.buttons["home.more"].tap(); app.buttons["仅限媒体"].tap()
        XCTAssertTrue(find(app,"media.open.timelinegif").waitForExistence(timeout: 10)); app.terminate()
        app = launch(flags)
        XCTAssertTrue(app.buttons["world.following"].isSelected)
        XCTAssertTrue(find(app,"media.open.timelinegif").waitForExistence(timeout: 10))
        XCTAssertFalse(find(app,"note.open.at4tltest0025").exists)
        puboSelectTab(app, "我的")
        puboTapVisible(app, "me.accounts")
        app.buttons["accounts.select.syntheticsecond"].tap()
        puboSelectTab(app, "世界圈")
        XCTAssertTrue(app.buttons["world.recommended"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["world.recommended"].isSelected)
        XCTAssertTrue(find(app,"note.open.at4tltest0025").waitForExistence(timeout: 10))
        capture(app,"local-account-preferences-isolated"); app.terminate()
    }
    func testUnavailableLocalFallsBackAndFailedReadCanRetry() {
        var app = launch(["--timeline-local-disabled"])
        XCTAssertTrue(app.staticTexts["公开内容暂不可用，已切换到关注。"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["world.following"].isSelected); capture(app,"local-unavailable-fallback"); app.terminate()
        app = launch(["--timeline-offline-first"])
        let retry = app.buttons["重试"]; XCTAssertTrue(retry.waitForExistence(timeout: 10)); retry.tap()
        XCTAssertTrue(find(app,"note.open.at4tltest0025").waitForExistence(timeout: 10)); capture(app,"local-retry-restored"); app.terminate()
    }
    func testH5FilterExclusionDoesNotSilentlyReplaceSelection() {
        let app = launch()
        app.buttons["home.more"].tap(); app.buttons["仅限媒体"].tap()
        app.buttons["home.more"].tap()
        XCTAssertTrue(app.buttons["在时间线中显示对他人的回复"].exists)
        XCTAssertFalse(app.buttons["在时间线中显示对他人的回复"].isEnabled)
        XCTAssertTrue(app.buttons["仅限媒体"].isEnabled)
        capture(app, "local-media-filter-exclusion")
        app.buttons["仅限媒体"].tap()
        app.buttons["home.more"].tap(); app.buttons["在时间线中显示对他人的回复"].tap()
        app.buttons["home.more"].tap()
        XCTAssertTrue(app.buttons["仅限媒体"].exists)
        XCTAssertFalse(app.buttons["仅限媒体"].isEnabled)
        XCTAssertTrue(app.buttons["在时间线中显示对他人的回复"].isEnabled)
        capture(app, "local-replies-filter-exclusion"); app.terminate()
    }
    func testOlderFailureRetriesAtReadingPositionWithoutDroppingPosts() {
        let app = launch(["--timeline-older-failure"])
        let retry = reveal(app, "timeline.retryOlder")
        if !retry.exists {
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "pagination-retry-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(retry.isHittable)
        XCTAssertFalse(app.buttons["timeline.refreshRetry"].exists)
        capture(app, "local-pagination-inline-retry")
        // Queued row-appearance callbacks must not retry behind the reader's back.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(find(app, "note.open.at4tltest0001").exists)
        retry.tap()
        XCTAssertTrue(reveal(app, "note.open.at4tltest0001").exists)
        XCTAssertFalse(app.buttons["timeline.retryOlder"].exists)
        capture(app, "local-pagination-recovered")
        // Recovery must append history, not replace the already loaded first page.
        let original = find(app, "note.open.at4tltest0025")
        for _ in 0..<32 where !original.isHittable { app.scrollViews["timeline.scroll"].swipeDown() }
        XCTAssertTrue(original.exists)
        XCTAssertTrue(original.isHittable)
        capture(app, "local-pagination-original-preserved"); app.terminate()
    }

    func testInitialFailureThenShortPageEndsPagination() {
        let app = launch(["--timeline-offline-first", "--timeline-short-page"])
        let retry = app.buttons["重试"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10)); retry.tap()
        XCTAssertTrue(find(app, "note.open.at4tltest0025").waitForExistence(timeout: 10))
        for _ in 0..<12 where !app.staticTexts["已显示全部帖子"].isHittable { app.scrollViews["timeline.scroll"].swipeUp() }
        XCTAssertTrue(app.staticTexts["已显示全部帖子"].exists)
        capture(app, "local-initial-retry-short-page"); app.terminate()
    }

}
