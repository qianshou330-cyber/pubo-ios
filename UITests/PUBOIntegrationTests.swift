import XCTest

/// Exercises the native UI against the pinned real backend on this runner's loopback network.
@MainActor final class PUBOIntegrationTests: XCTestCase {
    func testRealTimelineReplyAndRenoteButtons() async throws {
        let data = try await context(); let id = data["noteId"]!
        var app = launch(data)
        puboSelectTab(app, "世界圈")
        XCTAssertTrue(app.buttons["world.recommended"].waitForExistence(timeout: 20))
        let reply = app.buttons["note.reply." + id]
        for _ in 0..<10 where !reply.isHittable { app.swipeUp() }
        XCTAssertTrue(reply.isHittable); reply.tap()
        let editor = app.textViews["compose.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.tap(); editor.typeText("Native timeline reply proof")
        app.buttons["compose.send"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 15))
        let replied = try await proof("timelineReplied"); XCTAssertTrue(replied)
        capture(app, "joint-timeline-reply-receipt"); app.terminate()
        app = launch(data)
        puboSelectTab(app, "世界圈")
        XCTAssertTrue(app.buttons["world.recommended"].waitForExistence(timeout: 20))
        let renote = app.buttons["note.renote." + id]
        for _ in 0..<10 where !renote.isHittable { app.swipeUp() }
        XCTAssertTrue(renote.isHittable); renote.tap(); app.buttons["转发"].tap()
        XCTAssertTrue(app.staticTexts["已转发"].waitForExistence(timeout: 15))
        let renoted = try await proof("timelineRenoted"); XCTAssertTrue(renoted)
        capture(app, "joint-timeline-renote-receipt"); app.terminate()
    }
    func testRealLocalTimelineReactionAndCancellation() async throws {
        let data = try await context(); let app = launch(data)
        puboSelectTab(app, "世界圈")
        XCTAssertTrue(app.buttons["world.recommended"].waitForExistence(timeout: 20)); XCTAssertTrue(app.buttons["world.recommended"].isSelected)
        let reaction = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "note.reaction." + data["noteId"]! + ".")).firstMatch
        for _ in 0..<8 where !reaction.isHittable { app.swipeUp() }
        XCTAssertTrue(reaction.isHittable); reaction.tap()
        XCTAssertTrue(app.buttons["取消反应"].waitForExistence(timeout: 15))
        let created = try await proof("timelineReacted"); XCTAssertTrue(created); capture(app,"joint-timeline-reacted")
        reaction.tap(); let confirm = app.buttons.matching(identifier: "note.confirmReaction." + data["noteId"]!).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.buttons["取消反应"].waitForNonExistence(timeout: 15))
        let removed = try await proof("timelineUnreacted"); XCTAssertTrue(removed); app.terminate()
    }
    func testRealLocalTimelineReceivesAndDeletesSpecificNote() async throws {
        let app = launch(try await context())
        puboSelectTab(app, "世界圈")
        XCTAssertTrue(app.buttons["world.recommended"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["poll.choice.0"].waitForExistence(timeout: 20))
        var create = URLRequest(url: URL(string: "http://127.0.0.1:61913/timeline-create")!); create.httpMethod = "POST"; create.timeoutInterval = 15
        let (bytes, response) = try await URLSession.shared.data(for: create); XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
        let value = try JSONDecoder().decode([String:String].self,from:bytes)
        let note = app.descendants(matching:.any).matching(identifier:"note.open." + value["id"]!).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout:15)); capture(app,"joint-timeline-live-insert")
        var remove = URLRequest(url: URL(string:"http://127.0.0.1:61913/timeline-delete")!); remove.httpMethod = "POST"; remove.timeoutInterval = 15
        let (_, deleted) = try await URLSession.shared.data(for:remove); XCTAssertEqual((deleted as? HTTPURLResponse)?.statusCode,204)
        XCTAssertTrue(note.waitForNonExistence(timeout:15)); capture(app,"joint-timeline-live-delete"); app.terminate()
    }
    func testRealNativeAdminCreatesAnnouncement() async throws {
        let data = try await context(); let app = XCUIApplication(); app.launchArguments = ["--isolated-backend"]
        app.launchEnvironment = ["PUBO_ISOLATED_TOKEN": data["adminToken"]!, "PUBO_TEST_ADMIN_PASSWORD": data["adminPassword"]!]; app.launch()
        puboSelectTab(app, "我的")
        puboTapVisible(app, "me.settings")
        let entry = app.buttons["admin.entry"]; for _ in 0..<7 where !entry.isHittable { app.swipeUp() }; entry.tap()
        XCTAssertTrue(app.buttons["admin.authorize"].waitForExistence(timeout: 5)); app.buttons["admin.authorize"].tap()
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("公告")
        app.buttons["admin.operation.admin/announcements/create"].tap()
        for (field, content) in [("text", "Native administrator body"), ("title", "Native administrator announcement")] {
            let target = app.descendants(matching: .any).matching(identifier: "admin.field." + field).firstMatch
            for _ in 0..<10 where !target.isHittable { app.swipeUp() }; XCTAssertTrue(target.isHittable); target.tap(); target.typeText(content)
        }
        let submit = app.buttons["admin.submit"]; for _ in 0..<7 where !submit.isHittable { app.swipeUp() }; submit.tap()
        XCTAssertTrue(app.buttons["确认提交"].waitForExistence(timeout: 5)); app.buttons["确认提交"].tap()
        let result = app.staticTexts["admin.status"]; for _ in 0..<10 where !result.isHittable { app.swipeDown() }; XCTAssertTrue(result.waitForExistence(timeout: 10)); XCTAssertTrue(result.label.contains("已受理"))
        let saved = try await proof("adminAnnouncementCreated"); XCTAssertTrue(saved)
    }
    private func openAccountSettings(_ app: XCUIApplication) {
        puboSelectTab(app, "我的")
        let target = app.buttons["账号与隐私设置"]; for _ in 0..<5 where !target.isHittable { app.swipeUp() }; XCTAssertTrue(target.isHittable); target.tap()
    }
    func testRealPrivacyUpdate() async throws {
        let app = launch(try await context()); openAccountSettings(app); app.buttons["隐私与内容偏好"].tap()
        let toggle = app.switches["privacy.hideOnlineStatus"]; XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed); XCTAssertEqual(toggle.value as? String, "0")
        // Address the native switch exposed inside the SwiftUI row, not a stale row coordinate.
        let control = toggle.switches.firstMatch; XCTAssertTrue(control.waitForExistence(timeout: 5)); control.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let save = app.buttons["保存修改"]; for _ in 0..<6 where !save.isHittable { app.swipeUp() }; save.tap()
        XCTAssertTrue(app.staticTexts["已保存"].waitForExistence(timeout: 10)); let saved = try await proof("privacyChanged"); XCTAssertTrue(saved)
    }
    func testRealInvitationCreation() async throws {
        let app = launch(try await context()); openAccountSettings(app); app.buttons["邀请"].tap()
        XCTAssertTrue(app.buttons["创建邀请码"].waitForExistence(timeout: 10)); app.buttons["创建邀请码"].tap(); app.buttons["确认创建"].tap()
        XCTAssertTrue(app.buttons["删除邀请码"].waitForExistence(timeout: 10)); let saved = try await proof("invitationCreated"); XCTAssertTrue(saved)
    }
    func testRealMuteCreateAndRemove() async throws {
        let app = launch(try await context()); openAccountSettings(app); app.buttons["静音与屏蔽"].tap(); app.buttons["添加用户"].tap()
        let field = app.textFields["userPicker.query"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("native_bob")
        app.staticTexts["隔离测试朋友"].firstMatch.tap()
        let confirmation = app.alerts.buttons["确认"]; XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: confirmation); XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        confirmation.tap(); XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["移除"].waitForExistence(timeout: 10)); let saved = try await proof("muted"); XCTAssertTrue(saved)
        app.buttons["移除"].tap(); app.buttons["确认移除"].tap(); XCTAssertTrue(app.buttons["移除"].waitForNonExistence(timeout: 10)); let removed = try await proof("notMuted"); XCTAssertTrue(removed)
    }
    func testRealContactGroupCreation() async throws {
        let app = launch(try await context())
        puboSelectTab(app, "好友"); puboTapVisible(app, "friends.contacts"); app.buttons["新建分组"].tap()
        let name = app.alerts.textFields["分组名称"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Native contacts proof"); app.alerts.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["Native contacts proof"].waitForExistence(timeout: 10)); let saved = try await proof("contactsCreated"); XCTAssertTrue(saved); capture(app,"joint-native-contacts")
    }
    func testRealExistingRoomMessageAndBackendReceipt() async throws {
        let data = try await context()
        let nonce = UUID().uuidString
        let expected = "Native room message proof " + nonce
        let before = try await roomMessageProof(nonce)
        XCTAssertEqual(before.roomId, data["roomId"])
        XCTAssertTrue(before.messageIds.isEmpty, "A new nonce must have no existing receipt")
        let app = launch(data)
        XCTAssertFalse(app.buttons["chat.start"].exists)
        openParityRoom(app, data)
        XCTAssertFalse(app.buttons["创建群聊"].exists)
        let text = app.textViews["room.input"]
        XCTAssertTrue(text.waitForExistence(timeout: 10)); text.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        text.typeText(expected)
        let input = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.textViews["room.input"].value as? String == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [input], timeout: 10), .completed)
        app.buttons["room.send"].tap()
        XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 10))
        let after = try await roomMessageProof(nonce)
        XCTAssertEqual(after.roomId, data["roomId"])
        XCTAssertEqual(after.messageIds.count, 1, "Exactly one real backend message must match this attempt")
        XCTAssertTrue(after.messageIds.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(Set(after.messageIds).isDisjoint(with: Set(before.messageIds)))
        capture(app,"joint-native-existing-room-new-message-receipt")
        app.terminate()
    }
    private struct RoomMessageReceipt: Decodable {
        let roomId: String
        let messageIds: [String]
    }
    private func roomMessageProof(_ nonce: String) async throws -> RoomMessageReceipt {
        var url = URLComponents(string: "http://127.0.0.1:61913/room-message-proof")!
        url.queryItems = [URLQueryItem(name: "nonce", value: nonce)]
        let (data, response) = try await URLSession.shared.data(from: url.url!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONDecoder().decode(RoomMessageReceipt.self, from: data)
    }
    func testRealClipCreation() async throws {
        let app = launch(try await context())
        puboOpenDiscovery(app); puboTapVisible(app, "剪藏"); app.buttons["创建剪藏"].tap()
        let name = app.textFields["名称"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Native clip proof"); app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["Native clip proof"].waitForExistence(timeout: 10)); let saved = try await proof("clipCreated"); XCTAssertTrue(saved); capture(app,"joint-native-clip")
    }
    func testRealDriveFolderCreation() async throws {
        let app = launch(try await context())
        puboSelectTab(app, "我的"); app.buttons["网盘"].tap(); app.buttons["网盘新增"].tap(); app.buttons["新建文件夹"].tap()
        let name = app.alerts.textFields["文件夹名称"]; name.tap(); name.typeText("Native folder proof"); app.alerts.buttons["创建"].tap()
        XCTAssertTrue(app.staticTexts["Native folder proof"].waitForExistence(timeout: 10)); let saved = try await proof("folderCreated"); XCTAssertTrue(saved); capture(app,"joint-native-folder")
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    private func context() async throws -> [String: String] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:61913/context")!)
        request.timeoutInterval = 15
        let data: Data
        do {
            var reset = URLRequest(url: URL(string: "http://127.0.0.1:61913/prepare-test")!); reset.httpMethod = "POST"; reset.timeoutInterval = 15
            let (_, response) = try await URLSession.shared.data(for: reset); XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
            (data, _) = try await URLSession.shared.data(for: request)
        }
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
        let data = try await context(); let app = launch(data)
        puboOpenDiscovery(app)
        puboTapVisible(app, "搜索")
        let field = app.textFields["search.query"]; XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("PUBO joint proof\n")
        let result = app.descendants(matching: .any).matching(identifier: "note.open." + data["noteId"]!).firstMatch
        guard result.waitForExistence(timeout: 15) else { capture(app,"joint-search-failure"); XCTFail("Search must return the real seeded post ID"); return }
        let text = result.descendants(matching: .textView).firstMatch
        XCTAssertEqual(text.label, "PUBO joint proof #PUBO")
        app.buttons["note.more." + data["noteId"]!].tap()
        let save = app.buttons["note.favorite." + data["noteId"]!]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertTrue(save.isHittable); save.tap()
        XCTAssertTrue(app.staticTexts["已收藏"].waitForExistence(timeout: 10)); capture(app,"joint-real-search-favorite")
        let saved = try await proof("favorite"); XCTAssertTrue(saved)
    }
    func testRealVoteAndBackendReceipt() async throws {
        let app = launch(try await context())
        puboSelectTab(app, "世界圈")
        XCTAssertTrue(app.buttons["world.recommended"].waitForExistence(timeout: 20)); app.buttons["world.recommended"].tap()
        let choice = app.buttons["poll.choice.0"]
        for _ in 0..<6 where !choice.isHittable { app.swipeUp() }
        XCTAssertTrue(choice.waitForExistence(timeout: 10)); choice.tap()
        XCTAssertTrue(app.staticTexts["1 票 · 单选"].waitForExistence(timeout: 10)); capture(app,"joint-real-vote")
        let saved = try await proof("voted"); XCTAssertTrue(saved)
    }
    func testRealHistoricalContextDoesNotMarkRead() async throws {
        let data = try await context(); let app = launch(data)
        puboSelectTab(app, "消息")
        let peer = app.staticTexts["历史引用验收朋友"].firstMatch
        XCTAssertTrue(peer.waitForExistence(timeout: 10)); peer.tap()
        let quote = app.buttons["chat.reference." + data["quoteId"]!]
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
        XCTAssertTrue(quote.isHittable, "Opening a long conversation must expose its latest quoted message")
        capture(app,"joint-latest-quote-visible")
        XCTAssertLessThanOrEqual(quote.frame.maxY, app.textViews["chat.input"].frame.minY, "Reference must not overlap the composer")
        quote.tap()
        XCTAssertTrue(app.staticTexts["正在查看历史消息，预取不会标记已读"].waitForExistence(timeout: 10))
        let unread = try await proof("contextUnread"); XCTAssertTrue(unread)
        capture(app,"joint-real-history-context")
        app.buttons["回到最新消息"].tap()
        XCTAssertTrue(app.staticTexts["正在查看历史消息，预取不会标记已读"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
    }
    func testRealScheduledCreateAndCancel() async throws {
        let app = launch(try await context())
        puboSelectTab(app, "世界圈")
        XCTAssertTrue(app.buttons["home.compose"].waitForExistence(timeout: 20)); app.buttons["home.compose"].tap()
        let text = app.textViews["compose.text"]; text.tap(); text.typeText("Native scheduled proof")
        app.buttons["compose.more"].tap(); app.buttons["定时发布"].tap(); app.buttons["compose.send"].tap(); XCTAssertTrue(text.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.buttons["home.compose"].waitForExistence(timeout: 10))
        let created = try await proof("scheduled"); XCTAssertTrue(created)
        puboSelectTab(app, "我的"); app.buttons["定时帖子"].tap()
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
        puboOpenDiscovery(app)
        let edit = app.buttons["修改公告"]; XCTAssertTrue(edit.waitForExistence(timeout: 20)); edit.tap(); app.buttons["修改：隔离原生公告"].tap()
        XCTAssertTrue(app.buttons["admin.authorize"].waitForExistence(timeout: 10)); XCTAssertFalse(app.textFields["announcement.title"].exists)
        app.buttons["admin.authorize"].tap()
        let title = app.textFields["announcement.title"]; XCTAssertTrue(title.waitForExistence(timeout: 10)); title.tap(); title.typeText(" Edited")
        let save = app.buttons["保存修改"]; for _ in 0..<5 where !save.isHittable { app.swipeUp() }; save.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 10)); let changed = try await proof("announcementEdited"); XCTAssertTrue(changed)
        capture(app,"joint-real-admin-announcement")
    }
    func testRealChatEditRecallAndReaction() async throws {
        let app = launch(try await context())
        puboSelectTab(app, "消息")
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
    private func openParityRoom(_ app: XCUIApplication, _ data: [String: String]) {
        puboSelectTab(app, "消息")
        let row = app.buttons["conversation.room:" + data["roomId"]!]
        for _ in 0..<5 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 12)); row.tap()
        XCTAssertTrue(app.textViews["room.input"].waitForExistence(timeout: 10))
    }
    private func chatProof(_ key: String) async throws -> Bool {
        let (bytes, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:61913/chat-proof")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONDecoder().decode([String: Bool].self, from: bytes)[key] ?? false
    }
    func testRealGroupMemberReactionAndReportReceipt() async throws {
        let data = try await context(), app = launch(data); openParityRoom(app, data)
        let menu = app.buttons["room.menu." + data["roomMessageId"]!]
        XCTAssertTrue(menu.waitForExistence(timeout: 8)); XCTAssertTrue(menu.isHittable, "Opening a long group must expose the latest message menu"); capture(app,"joint-group-latest-visible"); menu.tap(); app.buttons["添加反应"].tap()
        XCTAssertTrue(app.buttons["❤️"].waitForExistence(timeout: 5)); app.buttons["❤️"].tap()
        let remove = app.buttons["取消反应 ❤"]; XCTAssertTrue(remove.waitForExistence(timeout: 12))
        let reacted = try await chatProof("reacted"); XCTAssertTrue(reacted); capture(app, "joint-group-member-reacted")
        remove.tap(); XCTAssertTrue(remove.waitForNonExistence(timeout: 12)); let unreacted = try await chatProof("unreacted"); XCTAssertTrue(unreacted)
        menu.tap(); app.buttons["举报"].tap(); let reason = app.textViews["report.reason"]; XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertTrue((reason.value as? String)?.contains("/chat/messages/" + data["roomMessageId"]!) == true)
        reason.tap(); reason.typeText("Synthetic native group report"); capture(app, "joint-group-report-preview"); app.buttons["提交"].tap()
        XCTAssertTrue(reason.waitForNonExistence(timeout: 12)); let reported = try await chatProof("reported"); XCTAssertTrue(reported)
    }
    func testRealGroupSearchLocatesHistoricalMessage() async throws {
        let data = try await context(), app = launch(data); openParityRoom(app, data)
        app.buttons["room.tab.search"].tap(); let field = app.textFields["chat.search.query"]; XCTAssertTrue(field.waitForExistence(timeout: 6)); field.tap(); field.typeText("Native historical group target")
        let result = app.staticTexts["Native historical group target"]; XCTAssertTrue(result.waitForExistence(timeout: 12)); result.tap()
        let target = app.descendants(matching: .any).matching(identifier: "room.bubble." + data["roomOldId"]!).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 12)); XCTAssertTrue(target.isHittable); capture(app, "joint-group-exact-history")
        app.buttons["回到最新消息"].tap(); XCTAssertTrue(app.staticTexts["Native ordinary member reaction"].waitForExistence(timeout: 10))
        XCTAssertTrue(target.waitForNonExistence(timeout: 5), "Returning to latest must restart paging rather than join two windows with an unloaded gap")
    }
    func testRealGroupSpecificArrivalAndDeletion() async throws {
        let data = try await context(), app = launch(data); openParityRoom(app, data)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:61913/chat-event")!); request.httpMethod = "POST"
        let (bytes, response) = try await URLSession.shared.data(for: request); XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let event = try JSONDecoder().decode([String: String].self, from: bytes)
        let target = app.descendants(matching: .any).matching(identifier: "room.bubble." + event["id"]!).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 12)); capture(app, "joint-group-live-arrival")
        request.url = URL(string: "http://127.0.0.1:61913/chat-delete")!
        let (_, deleted) = try await URLSession.shared.data(for: request); XCTAssertEqual((deleted as? HTTPURLResponse)?.statusCode, 204)
        XCTAssertTrue(target.waitForNonExistence(timeout: 12)); let removed = try await chatProof("liveDeleted"); XCTAssertTrue(removed); capture(app, "joint-group-live-deleted")
    }

}
