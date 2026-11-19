import XCTest

/// Optional simulator diagnostics, not a production smoothness acceptance gate.
final class WorldScrollDiagnosticUITests: XCTestCase {
    private var observedApp: XCUIApplication?
    private var stage = "not-launched"
    override func setUpWithError() throws { continueAfterFailure = false }

    private func note(_ text: String, name: String) {
        let item = XCTAttachment(string: text)
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
    override func tearDownWithError() throws {
        note("stage=\(stage)\nSimulator diagnostic only; missing measurements are UNAVAILABLE, not zero hitches or a smoothness pass.", name: "world-scroll-final-stage")
        if let app = observedApp {
            capture(app, "world-scroll-final-" + stage)
            app.terminate()
        }
        observedApp = nil
        try super.tearDownWithError()
    }
    private func launch() -> XCUIApplication {
        observedApp?.terminate()
        let app = XCUIApplication(); observedApp = app
        stage = "launch"
        app.launchArguments = ["--ui-testing", "--timeline-align", "--gif-preview"]
        app.launch(); puboSelectTab(app, "世界圈")
        XCTAssertTrue(app.buttons["world.more"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.scrollViews["timeline.scroll"].waitForExistence(timeout: 10))
        let newest = app.descendants(matching: .any).matching(identifier: "note.open.at4tltest0025").firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 10))
        XCTAssertTrue(newest.isHittable, "Each launch must start at the newest fixture, not a retained old-page offset")
        return app
    }
    private func visible(_ item: XCUIElement, app: XCUIApplication) -> Bool {
        guard item.exists && item.isHittable else { return false }
        let scroll = app.scrollViews["timeline.scroll"].frame
        let bar = app.descendants(matching: .any).matching(identifier: "app.tabBar").firstMatch.frame
        let upper = max(scroll.minY, app.buttons["home.more"].frame.maxY + 12)
        let lower = min(scroll.maxY, bar.minY - 16)
        let frame = item.frame
        return frame.midY > upper && frame.midY < lower && frame.midX > scroll.minX && frame.midX < scroll.maxX
    }

    func testSyntheticWorldCrossPageAndReadingPosition() {
        let app = launch()
        let scroll = app.scrollViews["timeline.scroll"]
        let oldest = app.descendants(matching: .any).matching(identifier: "note.open.at4tltest0001").firstMatch
        stage = "cross-page"
        var gestures = 0
        // Same bounded real gesture pattern as LocalTimelineUITests.reveal.
        for _ in 0..<32 {
            if visible(oldest, app: app) { break }
            let reverse = oldest.exists && oldest.frame.midY <= max(scroll.frame.minY, app.buttons["home.more"].frame.maxY + 12)
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: reverse ? 0.40 : 0.72))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: reverse ? 0.72 : 0.40))
            start.press(forDuration: 0.05, thenDragTo: end)
            gestures += 1
        }
        note("gestures=\(gestures) target=at4tltest0001\n25 source records, limit20; filtering may reduce count. Reachability is not a hitch measurement.", name: "world-cross-page-gestures")
        XCTAssertGreaterThan(gestures, 0)
        XCTAssertTrue(visible(oldest, app: app), "Oldest fixture must actually enter the unobscured viewport")
        let before = oldest.frame
        capture(app, "world-oldest-before-detail")
        stage = "oldest-detail"
        oldest.tap()
        XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        stage = "oldest-return"
        XCTAssertTrue(oldest.waitForExistence(timeout: 8))
        XCTAssertTrue(visible(oldest, app: app), "Returning must retain the historical reading region")
        note("before=\(before) after=\(oldest.frame)\nObserved frame delta only; no pixel-exact position claim.", name: "world-reading-position")
        capture(app, "world-oldest-after-return")
        stage = "cross-page-completed"
    }

    func testSyntheticWorldScrollSignpostSamples() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        var sample = 0
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            sample += 1
            let app = launch() // New app process before every sample, outside measurement.
            let scroll = app.scrollViews["timeline.scroll"]
            stage = "sample-\(sample)-ready"
            capture(app, "world-scroll-sample-\(sample)-before")
            stage = "sample-\(sample)-measuring"
            startMeasuring()
            for _ in 0..<3 { scroll.swipeUp() }
            stopMeasuring()
            stage = "sample-\(sample)-measured"
            capture(app, "world-scroll-sample-\(sample)-after")
            note("sample=\(sample) gestures=3\nFresh process and verified newest-row start; persistent/OS caches are not cleared. First-page scroll sample, not cross-page latency. Raw signpost values must be read from xcresult. No baseline/threshold and no physical-device conclusion.", name: "world-scroll-sample-\(sample)-scope")
            app.terminate(); observedApp = nil
        }
        stage = "samples-completed-not-smoothness-certified"
    }
}
