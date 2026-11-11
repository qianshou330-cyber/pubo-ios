import XCTest

final class TimelineNavigationEvidenceTests: XCTestCase {
    func testTopDestinationsAndReturnToTheSelectedTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--timeline-align", "--gif-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["timeline.local"].waitForExistence(timeout: 15))
        for destination in ["列表", "天线", "频道"] {
            let link = app.buttons.matching(identifier: destination).firstMatch
            XCTAssertTrue(link.isHittable, destination)
            link.tap()
            let bar = app.navigationBars[destination]
            XCTAssertTrue(bar.waitForExistence(timeout: 8), destination)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "top-" + destination
            shot.lifetime = .keepAlways
            add(shot)
            bar.buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons["timeline.local"].isSelected)
            XCTAssertEqual(app.tabBars.buttons.count, 4)
        }
    }

    func testVisibleInsertionAndRemovalRecording() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--timeline-align", "--gif-preview", "--timeline-events"]
        app.launch()
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
