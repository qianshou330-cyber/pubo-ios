import XCTest

final class TimelineNavigationEvidenceTests: XCTestCase {
    func testTopDestinationsAndReturnToTheSelectedTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--timeline-align", "--gif-preview"]
        app.launch()
        puboSelectTab(app, "世界圈")
        XCTAssertTrue(app.buttons["world.recommended"].waitForExistence(timeout: 15))
        for destination in ["我的主页", "列表", "天线", "频道"] {
            if destination == "我的主页" { puboSelectTab(app, "我的") }
            else { puboOpenDiscovery(app) }
            let link = app.buttons.matching(identifier: destination == "我的主页" ? "me.profile" : destination).firstMatch
            XCTAssertTrue(link.waitForExistence(timeout: 8), destination)
            for _ in 0..<10 where !link.isHittable { app.swipeUp() }
            XCTAssertTrue(link.isHittable, destination)
            XCTAssertGreaterThanOrEqual(link.frame.width, 44)
            XCTAssertGreaterThanOrEqual(link.frame.height, 44)
            link.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.18)).tap()
            let bar = app.navigationBars[destination]
            XCTAssertTrue(bar.waitForExistence(timeout: 8), destination)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "top-" + destination
            shot.lifetime = .keepAlways
            add(shot)
            bar.buttons.firstMatch.tap()
            if destination != "我的主页" {
                XCTAssertTrue(app.navigationBars["发现"].waitForExistence(timeout: 8))
                app.navigationBars["发现"].buttons.firstMatch.tap()
            }
            puboSelectTab(app, "世界圈")
            XCTAssertTrue(app.buttons["world.recommended"].isSelected)
            for title in ["消息", "好友", "世界圈", "我的"] { XCTAssertTrue(puboTab(app, title).exists) }
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "app.tab.")).count, 4)
        }
    }

    func testVisibleInsertionAndRemovalRecording() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--timeline-align", "--gif-preview", "--timeline-events"]
        app.launch()
        puboSelectTab(app, "世界圈")
        let original = app.descendants(matching: .any).matching(identifier: "note.open.at4tltest0025").firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 15))
        app.buttons["home.more"].tap()
        app.buttons["测试新帖"].tap()
        let incoming = app.descendants(matching: .any).matching(identifier: "note.open.zznewtimeline0001").firstMatch
        XCTAssertTrue(incoming.waitForExistence(timeout: 6))
        XCTAssertTrue(incoming.isHittable)
        app.buttons["home.more"].tap()
        app.buttons["测试删除原帖"].tap()
        XCTAssertTrue(original.waitForNonExistence(timeout: 8))
        XCTAssertTrue(incoming.isHittable)
    }
}
