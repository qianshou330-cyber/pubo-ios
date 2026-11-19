#if DEBUG && PUBO_SPARSE_WORLD_PROBE
import XCTest

final class SparseWorldUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func rows(_ app: XCUIApplication) throws -> [String:Double] {
        let s = app.scrollViews["timeline.scroll"].frame
        let top = max(s.minY,app.buttons["home.more"].frame.maxY+4)
        let bottom = min(s.maxY,app.descendants(matching:.any).matching(identifier:"app.tabBar").firstMatch.frame.minY-4)
        var result: [String: Double] = [:]
        for node in puboSnapshotDescendants(try app.snapshot()) {
            let key = node.identifier, rect = node.frame
            guard key.hasPrefix("note.open.w80-"), let n = Int(String(key.suffix(4))),
                  (1...200).contains(n), key == String(format:"note.open.w80-%04d",n),
                  rect.width>0, rect.height>0, rect.midX>s.minX, rect.midX<s.maxX,
                  rect.midY>top, rect.midY<bottom else { continue }
            result[key] = Double(rect.midY)
        }
        return result
    }
    func testActiveWorldRowCaptureAfterRealDrags() throws {
        let app = XCUIApplication(), nonce = UUID().uuidString
        app.launchArguments = ["--ui-testing","--timeline-align","--sparse-world-probe"]
        app.launchEnvironment["PUBO_SPARSE_NONCE"] = nonce
        app.launch(); puboSelectTab(app,"世界圈")
        let discover = app.buttons["world.more"]
        XCTAssertTrue(discover.waitForExistence(timeout:15))
        let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@", "sparse-ready"), object:discover)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:35),.completed, "Synthetic warm precondition not proven")
        let feed = app.scrollViews["timeline.scroll"]
        let before = try rows(app)
        XCTAssertFalse(before.isEmpty)
        shot(app,"sparse-before"); let baselineEnd = now
        var times: [[Double]] = []
        for _ in 0..<2 {
            let start = feed.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.74))
            let end = feed.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.38))
            let t = now; start.press(forDuration:0.05,thenDragTo:end); times.append([t,now])
        }
        let after = try rows(app)
        XCTAssertFalse(after.isEmpty)
        let moved = Set(before.keys) != Set(after.keys) || before.contains { k,v in abs((after[k] ?? v)-v)>8 }
        XCTAssertTrue(moved,"Viewport evidence did not advance; not an exercised scroll")
        shot(app,"sparse-after"); let finish = now
        let evidence: [String:Any] = ["nonce":nonce,"baselineEnd":baselineEnd,"drags":times,"end":finish,
                                      "before":before,"after":after]
        let data = try JSONSerialization.data(withJSONObject:evidence,options:[.sortedKeys])
        let a = XCTAttachment(data:data,uniformTypeIdentifier:"public.json");a.name="sparse-gestures";a.lifetime = .keepAlways; add(a)
        // Only after final observation, let the app flush bounded in-memory evidence.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for:.runningBackground,timeout:15) || app.state == .runningBackgroundSuspended)
    }
}
#endif
