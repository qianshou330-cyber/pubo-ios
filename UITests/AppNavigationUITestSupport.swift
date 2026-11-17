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

/// Flatten an already captured immutable tree; this performs no remote query.
func puboSnapshotDescendants(_ snapshot: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
    [snapshot] + snapshot.children.flatMap { puboSnapshotDescendants($0) }
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
        // Do not ask XCTest for an activation point while its AX window geometry is invalid.
        // This uses the same single 8-second readiness budget; invalid frames never pass.
        // Buffer diagnostics only: no extra AX reads, screenshots, sleeps or retries.
        // The cap limits storage, never the original predicate's evaluations.
        var samples: [(index: Int, start: TimeInterval, windowTime: TimeInterval,
                       frameTime: TimeInterval, hitTime: TimeInterval,
                       window: CGRect, frame: CGRect, finite: Bool,
                       windowPositive: Bool, framePositive: Bool,
                       intersects: Bool, hittable: Bool?)] = []
        samples.reserveCapacity(16)
        var evaluations = 0
        var phase = "not-started"
        var phaseStarted: TimeInterval = 0
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            evaluations += 1
            let sampleStart = Date().timeIntervalSince(started)
            phase = "window-frame"
            phaseStarted = sampleStart
            let window = app.windows.firstMatch.frame
            let afterWindow = Date().timeIntervalSince(started)
            phase = "button-frame"
            phaseStarted = afterWindow
            let frame = button.frame
            let afterFrame = Date().timeIntervalSince(started)
            let finite = [window.minX, window.minY, window.width, window.height,
                          frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite }
            let windowPositive = window.width > 0 && window.height > 0
            let framePositive = frame.width > 0 && frame.height > 0
            // Preserve the original short circuit before any hittability query.
            let intersects = finite && windowPositive && framePositive && window.intersects(frame)
            var hittable: Bool? = nil
            if intersects {
                phase = "button-hittable"
                phaseStarted = afterFrame
                hittable = button.isHittable
            }
            let afterHit = Date().timeIntervalSince(started)
            phase = "sample-complete"
            phaseStarted = afterHit
            if samples.count < 16 {
                samples.append((evaluations, sampleStart, afterWindow - sampleStart,
                                afterFrame - afterWindow, afterHit - afterFrame,
                                window, frame, finite, windowPositive, framePositive,
                                intersects, hittable))
            }
            return hittable == true
        }, object: button)
        let result = XCTWaiter.wait(for: [ready], timeout: 8)
        // Format and emit only after the unchanged waiter has returned.
        print("PUBO tab readiness diagnostics \(title): evaluations=\(evaluations), retained=\(samples.count), phase=\(phase), phaseStarted=\(phaseStarted)")
        for sample in samples {
            print("PUBO tab readiness sample \(title): index=\(sample.index), start=\(sample.start), windowSeconds=\(sample.windowTime), frameSeconds=\(sample.frameTime), hitSeconds=\(sample.hitTime), window=\(sample.window), frame=\(sample.frame), finite=\(sample.finite), windowPositive=\(sample.windowPositive), framePositive=\(sample.framePositive), intersects=\(sample.intersects), hittable=\(sample.hittable.map { String($0) } ?? "not-queried")")
        }
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


