import XCTest

/// Accept only floating-point representation noise at the required dimension,
/// not a smaller visual or touch target. At 44 pt the allowance is ~2.84e-14 pt.
func puboTouchDimensionMeetsMinimum(_ dimension: CGFloat, minimum: CGFloat = 44) -> Bool {
    dimension.isFinite && minimum.isFinite && minimum > 0 &&
        dimension >= minimum - minimum.ulp * 4
}

/// Compare endpoints instead of subtracting large screen coordinates into a
/// dimension. CGRect subtraction can report a mathematically 44pt span as
/// 43.99999999999994; this preserves the actual 44pt endpoint requirement.
func puboTouchRectMeetsMinimum(_ frame: CGRect, minimum: CGFloat = 44) -> Bool {
    guard minimum.isFinite, minimum > 0,
          frame.origin.x.isFinite, frame.origin.y.isFinite,
          frame.width.isFinite, frame.height.isFinite,
          frame.width > 0, frame.height > 0 else { return false }
    let requiredX = frame.minX + minimum, requiredY = frame.minY + minimum
    guard frame.maxX.isFinite, frame.maxY.isFinite,
          requiredX.isFinite, requiredY.isFinite,
          requiredX > frame.minX, requiredY > frame.minY else { return false }
    return frame.maxX >= requiredX && frame.maxY >= requiredY
}

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
        let started = Date()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: button)
        let result = XCTWaiter.wait(for: [ready], timeout: 8)
        print("PUBO tab ready wait \(title): \(Date().timeIntervalSince(started))s, result=\(result.rawValue)")
        XCTAssertEqual(result, .completed, title, file: file, line: line)
        guard result == .completed else { return }
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
