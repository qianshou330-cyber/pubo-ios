import XCTest

/// Exercises the native UI against the pinned real backend on this runner's loopback network.
@MainActor final class PUBOIntegrationTests: XCTestCase {
    func testRealContactGroupCreation() async throws {
        let app = launch(try await context())
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 20)); app.tabBars.buttons["私信"].tap(); app.buttons["联系人"].tap(); app.buttons["新建分组"].tap()
        let name = app.alerts.textFields["分组名称"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Native contacts proof"); app.alerts.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["Native contacts proof"].waitForExistence(timeout: 10)); let saved = try await proof("contactsCreated"); XCTAssertTrue(saved); capture(app,"joint-native-contacts")
    }
    func testRealRoomCreationAndMessage() async throws {
        let app = launch(try await context())
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 20)); app.tabBars.buttons["私信"].tap(); app.buttons["群聊"].tap(); app.buttons["创建群聊"].tap()
        let name = app.textFields["群聊名称"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Native room proof"); app.buttons["保存群聊"].tap()
        let room = app.staticTexts["Native room proof"]; XCTAssertTrue(room.waitForExistence(timeout: 10)); room.tap()
        let text = app.textFields["群聊消息"]; XCTAssertTrue(text.waitForExistence(timeout: 10)); text.tap(); text.typeText("Native room message proof"); app.buttons["发送"].tap()
        XCTAssertTrue(app.staticTexts["Native room message proof"].waitForExistence(timeout: 10)); let saved = try await proof("roomMessageCreated"); XCTAssertTrue(saved); capture(app,"joint-native-room")
    }
    func testRealClipCreation() async throws {
        let app = launch(try await context())
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 20)); app.tabBars.buttons["我的"].tap(); app.buttons["更多功能"].tap(); app.buttons["剪藏"].tap(); app.buttons["创建剪藏"].tap()
        let name = app.textFields["名称"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Native clip proof"); app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["Native clip proof"].waitForExistence(timeout: 10)); let saved = try await proof("clipCreated"); XCTAssertTrue(saved); capture(app,"joint-native-clip")
    }
    func testRealDriveFolderCreation() async throws {
        let app = launch(try await context())
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 20)); app.tabBars.buttons["我的"].tap(); app.buttons["网盘"].tap(); app.buttons["网盘新增"].tap(); app.buttons["新建文件夹"].tap()
        let name = app.alerts.textFields["文件夹名称"]; name.tap(); name.typeText("Native folder proof"); app.alerts.buttons["创建"].tap()
        XCTAssertTrue(app.staticTexts["Native folder proof"].waitForExistence(timeout: 10)); let saved = try await proof("folderCreated"); XCTAssertTrue(saved); capture(app,"joint-native-folder")
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    private func context() async throws -> [String: String] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:61913/context")!)
        request.timeoutInterval = 15
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: request) }
        catch {
            if ProcessInfo.processInfo.environment["PUBO_REQUIRE_ISOLATED_BACKEND"] == "1" { throw error }
            throw XCTSkip("The disposable real backend is only started by the native-integration job.")
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
    private func launch(_ context: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-backend"]
        app.launchEnvironment = ["PUBO_ISOLATED_TOKEN": context["token"]!]
        app.launch(); return app
    }
    private func proof(_ key: String) async throws -> Bool {
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:61913/proof")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONDecoder().decode([String: Bool].self, from: data)[key] ?? false
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testRealSearchAndFavorite() async throws {
        let app = launch(try await context())
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 20)); app.tabBars.buttons["我的"].tap()
        app.buttons["搜索"].tap()
        let field = app.textFields["search.query"]; XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("PUBO joint proof\n")
        guard app.staticTexts["PUBO joint proof #PUBO"].waitForExistence(timeout: 15) else { capture(app,"joint-search-failure"); XCTFail("Search must return the real seeded post"); return }
        app.buttons["帖子更多操作"].firstMatch.tap(); app.buttons["收藏帖子"].tap()
        XCTAssertTrue(app.staticTexts["已收藏"].waitForExistence(timeout: 10)); capture(app,"joint-real-search-favorite")
        let saved = try await proof("favorite"); XCTAssertTrue(saved)
    }
    func testRealVoteAndBackendReceipt() async throws {
        let app = launch(try await context())
        XCTAssertTrue(app.buttons["timeline.local"].waitForExistence(timeout: 20)); app.buttons["timeline.local"].tap()
        let choice = app.buttons["poll.choice.0"]
        for _ in 0..<6 where !choice.isHittable { app.swipeUp() }
        XCTAssertTrue(choice.waitForExistence(timeout: 10)); choice.tap()
        XCTAssertTrue(app.staticTexts["1 票 · 单选"].waitForExistence(timeout: 10)); capture(app,"joint-real-vote")
        let saved = try await proof("voted"); XCTAssertTrue(saved)
    }
    func testRealHistoricalContextDoesNotMarkRead() async throws {
        let data = try await context(); let app = launch(data)
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 20)); app.tabBars.buttons["私信"].tap()
        let peer = app.staticTexts["历史引用验收朋友"].firstMatch
        XCTAssertTrue(peer.waitForExistence(timeout: 10)); peer.tap()
        let quote = app.buttons["chat.reference." + data["quoteId"]!]
        XCTAssertTrue(quote.waitForExistence(timeout: 10)); quote.tap()
        XCTAssertTrue(app.staticTexts["正在查看历史消息，预取不会标记已读"].waitForExistence(timeout: 10))
        let unread = try await proof("contextUnread"); XCTAssertTrue(unread)
        capture(app,"joint-real-history-context")
        app.buttons["回到最新消息"].tap()
        XCTAssertTrue(app.staticTexts["正在查看历史消息，预取不会标记已读"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
    }
    func testRealScheduledCreateAndCancel() async throws {
        let app = launch(try await context())
        XCTAssertTrue(app.buttons["home.compose"].waitForExistence(timeout: 20)); app.buttons["home.compose"].tap()
        let text = app.textViews["compose.text"]; text.tap(); text.typeText("Native scheduled proof")
        app.buttons["compose.more"].tap(); app.buttons["定时发布"].tap(); app.buttons["compose.send"].tap()
        XCTAssertTrue(app.buttons["home.compose"].waitForExistence(timeout: 10))
        let created = try await proof("scheduled"); XCTAssertTrue(created)
        app.tabBars.buttons["我的"].tap(); app.buttons["定时帖子"].tap()
        XCTAssertTrue(app.staticTexts["Native scheduled proof"].waitForExistence(timeout: 10)); capture(app,"joint-real-scheduled-note")
        app.buttons["取消定时，保留服务器草稿"].tap(); app.buttons["取消定时发布"].tap()
        XCTAssertTrue(app.staticTexts["暂无定时帖子"].waitForExistence(timeout: 10))
        let cancelled = try await proof("scheduledCancelled"); XCTAssertTrue(cancelled)
    }
    func testRealAdminAnnouncementUsesSameAccountReauthentication() async throws {
        let data = try await context(); let app = XCUIApplication()
        app.launchArguments = ["--isolated-backend", "--reduce-motion"]
        app.launchEnvironment = ["PUBO_ISOLATED_TOKEN": data["adminToken"]!, "PUBO_TEST_ADMIN_PASSWORD": data["adminPassword"]!]
        app.launch()
        let edit = app.buttons["修改公告"]; XCTAssertTrue(edit.waitForExistence(timeout: 20)); edit.tap(); app.buttons["隔离原生公告"].firstMatch.tap()
        XCTAssertTrue(app.buttons["admin.authorize"].waitForExistence(timeout: 10)); XCTAssertFalse(app.textFields["announcement.title"].exists)
        app.buttons["admin.authorize"].tap()
        let title = app.textFields["announcement.title"]; XCTAssertTrue(title.waitForExistence(timeout: 10)); title.tap(); title.typeText(" Edited")
        let save = app.buttons["保存修改"]; for _ in 0..<5 where !save.isHittable { app.swipeUp() }; save.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 10)); let changed = try await proof("announcementEdited"); XCTAssertTrue(changed)
        capture(app,"joint-real-admin-announcement")
    }
    func testRealChatEditRecallAndReaction() async throws {
        let app = launch(try await context())
        XCTAssertTrue(app.tabBars.buttons["私信"].waitForExistence(timeout: 20)); app.tabBars.buttons["私信"].tap()
        XCTAssertTrue(app.staticTexts["隔离测试朋友"].firstMatch.waitForExistence(timeout: 10)); app.staticTexts["隔离测试朋友"].firstMatch.tap()
        let message = app.staticTexts["原生编辑验收"]; XCTAssertTrue(message.waitForExistence(timeout: 10)); message.press(forDuration: 1)
        app.buttons["编辑／撤回消息"].tap(); XCTAssertTrue(app.buttons["编辑文字"].waitForExistence(timeout: 10)); app.buttons["编辑文字"].tap()
        let field = app.textViews["chat.edit.text"]; field.tap(); field.typeText(" Edited")
        let save = app.buttons["chat.edit.save"]; for _ in 0..<4 where !save.isHittable { app.swipeUp() }; save.tap()
        XCTAssertTrue(app.staticTexts["编辑已保存。"].waitForExistence(timeout: 10))
        let edited = try await proof("edited"); XCTAssertTrue(edited); capture(app,"joint-real-chat-edit")
        app.buttons["撤回消息"].tap(); app.buttons["撤回消息"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["消息已撤回"].waitForExistence(timeout: 10))
        let recalled = try await proof("recalled"); XCTAssertTrue(recalled)
        app.buttons["关闭"].tap()
        app.staticTexts["真实隔离后端私信"].press(forDuration: 1); app.buttons["消息反应／举报"].tap()
        XCTAssertTrue(app.buttons["添加反应"].waitForExistence(timeout: 10)); app.buttons["添加反应"].tap()
        XCTAssertTrue(app.buttons["❤️"].waitForExistence(timeout: 10)); app.buttons["❤️"].tap()
        let remove = app.buttons["chat.reaction.remove.❤"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10)); capture(app,"joint-real-chat-reaction")
        let reacted = try await proof("reacted"); XCTAssertTrue(reacted)
        remove.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: remove)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
        let unreacted = try await proof("unreacted"); XCTAssertTrue(unreacted)
    }
}
