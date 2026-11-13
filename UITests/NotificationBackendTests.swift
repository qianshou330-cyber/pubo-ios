import XCTest

@MainActor final class NotificationBackendTests: XCTestCase {
    private let service = URL(string: "http://127.0.0.1:61913")!

    func testReadingNotificationsAndOpeningMentionLists() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PUBO_CHECK_NOTIFICATIONS"] == "1", "Requires the isolated notification backend")
        let (data, _) = try await URLSession.shared.data(from: service.appendingPathComponent("notifications-context"))
        let fixture = try JSONDecoder().decode([String: String].self, from: data)
        let token = try XCTUnwrap(fixture["token"])
        let mentionID = try XCTUnwrap(fixture["mentionID"])
        let directID = try XCTUnwrap(fixture["directID"])
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-backend"]
        app.launchEnvironment["PUBO_ISOLATED_TOKEN"] = token
        app.launch()
        defer { app.terminate() }

        let entry = puboTab(app, "我的")
        XCTAssertTrue(entry.waitForExistence(timeout: 20))
        let before = try await serverReadState()
        XCTAssertFalse(before, "Opening the messages landing page must preserve the notification badge")
        puboOpenNotifications(app)
        XCTAssertTrue(app.buttons["notifications.tab.all"].waitForExistence(timeout: 10))
        var read = false
        for _ in 0..<24 {
            if try await serverReadState() { read = true; break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertTrue(read, "Opening notifications must acknowledge the actual backend unread state")
        app.buttons["notifications.tab.mentions"].tap()
        let publicMention = app.descendants(matching: .any).matching(identifier: "note.open." + mentionID).firstMatch
        let directMention = app.descendants(matching: .any).matching(identifier: "note.open." + directID).firstMatch
        XCTAssertTrue(publicMention.waitForExistence(timeout: 12))
        XCTAssertTrue(directMention.waitForExistence(timeout: 8))
        app.buttons["notifications.tab.directNotes"].tap()
        XCTAssertTrue(publicMention.waitForNonExistence(timeout: 12))
        XCTAssertTrue(directMention.waitForExistence(timeout: 8))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "real-notifications-specified"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func serverReadState() async throws -> Bool {
        let (data, response) = try await URLSession.shared.data(from: service.appendingPathComponent("notifications-read"))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(try JSONDecoder().decode([String: Bool].self, from: data)["read"])
    }
}
