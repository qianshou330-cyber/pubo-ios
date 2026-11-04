import XCTest

/// Supplemental real-loopback test; all writes are disposable, never production.
@MainActor final class ReconnectionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testForegroundReconnectRecoversMissedNoteAndDeletion() async throws {
        func request(_ path: String, method: String = "GET") async throws -> Data {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:61913/" + path)!)
            request.httpMethod = method; request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertTrue((200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0))
            return data
        }
        do { _ = try await request("prepare-test", method: "POST") }
        catch {
            if ProcessInfo.processInfo.environment["PUBO_REQUIRE_ISOLATED_BACKEND"] == "1" { throw error }
            throw XCTSkip("This test requires the disposable loopback backend.")
        }
        let context = try JSONDecoder().decode([String: String].self, from: await request("context"))
        let app = XCUIApplication(); app.launchArguments = ["--isolated-backend"]
        app.launchEnvironment = ["PUBO_ISOLATED_TOKEN": context["token"]!]; app.launch()
        XCTAssertTrue(app.buttons["timeline.local"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["poll.choice.0"].waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.state == .runningBackgroundSuspended)
        let created = try JSONDecoder().decode([String: String].self, from: await request("timeline-create", method: "POST"))
        app.activate()
        let note = app.descendants(matching: .any).matching(identifier: "note.open." + created["id"]!).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 20))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "note.open." + created["id"]!).count, 1)
        let recovered = XCTAttachment(screenshot: app.screenshot()); recovered.name = "reconnect-missed-note"; recovered.lifetime = .keepAlways; add(recovered)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.state == .runningBackgroundSuspended)
        _ = try await request("timeline-delete", method: "POST")
        app.activate()
        XCTAssertTrue(note.waitForNonExistence(timeout: 20))
        XCTAssertTrue(app.buttons["poll.choice.0"].waitForExistence(timeout: 15))
        let deleted = XCTAttachment(screenshot: app.screenshot()); deleted.name = "reconnect-missed-deletion"; deleted.lifetime = .keepAlways; add(deleted)
        app.terminate()
    }
}
