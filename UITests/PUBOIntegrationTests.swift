import XCTest

/// Exercises the native UI against the pinned real backend on this runner's loopback network.
@MainActor final class PUBOIntegrationTests: XCTestCase {
    private func context() async throws -> [String: String] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:61913/context")!)
        request.timeoutInterval = 2
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: request) }
        catch { throw XCTSkip("The disposable real backend is only started by the native-integration job.") }
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
        let field = app.searchFields.firstMatch; XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("PUBO joint proof\n")
        XCTAssertTrue(app.staticTexts["PUBO joint proof #PUBO"].waitForExistence(timeout: 15))
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
        XCTAssertTrue(app.buttons["取消 ❤️"].waitForExistence(timeout: 10)); capture(app,"joint-real-chat-reaction")
    }
}
