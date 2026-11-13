import XCTest

/// Navigate through actual controls only. Helpers never reset a path or modify
/// application state; callers retain responsibility for explicit Back actions.
extension XCTestCase {
    func puboTab(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let ids = ["消息": "messages", "好友": "friends", "世界圈": "world", "我的": "me"]
        return app.buttons["app.tab." + (ids[title] ?? title)]
    }
    func puboSelectTab(_ app: XCUIApplication, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = puboTab(app, title)
        XCTAssertTrue(button.waitForExistence(timeout: 20), title, file: file, line: line)
        XCTAssertTrue(button.isHittable, title, file: file, line: line)
        button.tap()
        XCTAssertTrue(button.isSelected, title, file: file, line: line)
    }
    func puboTapVisible(_ app: XCUIApplication, _ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = app.descendants(matching: .any).matching(identifier: id).firstMatch
        _ = target.waitForExistence(timeout: 5)
        for _ in 0..<10 where !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.waitForExistence(timeout: 10), id, file: file, line: line)
        XCTAssertTrue(target.isHittable, id, file: file, line: line)
        target.tap()
    }
    func puboOpenNotifications(_ app: XCUIApplication) {
        puboSelectTab(app, "我的")
        puboTapVisible(app, "me.notifications")
        XCTAssertTrue(app.buttons["notifications.filter"].waitForExistence(timeout: 10))
    }
    func puboOpenDiscovery(_ app: XCUIApplication) {
        puboSelectTab(app, "世界圈")
        puboTapVisible(app, "world.more")
        XCTAssertTrue(app.navigationBars["发现"].waitForExistence(timeout: 10))
    }
}
