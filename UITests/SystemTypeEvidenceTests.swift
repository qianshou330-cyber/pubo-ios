import XCTest
import UIKit

final class SystemTypeEvidenceTests: XCTestCase {
    private let id = "at4tltest0025"
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNormalSystemContentSize() throws { try captureEvidence("normal") }
    func testAccessibilitySystemContentSize() throws { try captureEvidence("accessibility") }

    private func captureEvidence(_ phase: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--timeline-align", "--gif-preview", "--timeline-visual-header", "--reduce-motion"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["timeline.local"].waitForExistence(timeout: 18))
        let order = ["home", "local", "hybrid", "global"]
        let rects = order.map { app.buttons["timeline." + $0].frame }
        let vertical = rects[3].minY > rects[0].maxY
        XCTAssertEqual(vertical, phase == "accessibility", "Actual system setting must rearrange the selector.")
        let selectorCenters = rects.map { ["x": $0.midX, "y": $0.midY] }
        let signedHeader = try verifyHeader(app, phase: phase, guest: false)
        let body = reveal(app, "note.open." + id)
        let bodyRect = body.frame
        let firstText = (body.value as? String) ?? body.label
        capture(app, phase + "-text")
        let actions = ["note.reply.", "note.renote.", "note.addReaction.", "note.more."]
        var geometry: [[String: Any]] = []
        var previousRight: CGFloat?
        for prefix in actions {
            let button = reveal(app, prefix + id)
            let rect = button.frame
            geometry.append(["id": prefix + id, "x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height, "hittable": button.isHittable])
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(rect.width, 43.5)
            XCTAssertGreaterThanOrEqual(rect.height, 43.5)
            XCTAssertLessThanOrEqual(rect.maxX, app.frame.width)
            if let prior = previousRight { XCTAssertGreaterThanOrEqual(rect.minX, prior - 0.5) }
            previousRight = rect.maxX
        }
        capture(app, phase + "-actions")
        let signedDimensions = app.frame
        let signedArguments = app.launchArguments
        app.terminate()
        app.launchArguments = ["--ui-testing", "--logged-out", "--timeline-align", "--gif-preview", "--reduce-motion"]
        app.launch()
        XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout: 15))
        let guestHeader = try verifyHeader(app, phase: phase, guest: true)
        let values: [String: Any] = ["phase": phase, "fixture": id, "bodyText": firstText,
                                     "selectorVertical": vertical, "selectorCenters": selectorCenters,
                                     "signedHeader": signedHeader, "guestHeader": guestHeader,
                                     "bodyWidth": bodyRect.width, "bodyHeight": bodyRect.height,
                                     "deviceWidth": signedDimensions.width, "deviceHeight": signedDimensions.height,
                                     "actions": geometry, "arguments": signedArguments]
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = phase + "-geometry.json"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func verifyHeader(_ app: XCUIApplication, phase: String, guest: Bool) throws -> [String: Any] {
        let author = reveal(app, "note.author." + id)
        let names = guest ? "测试朋友" : "这是一个需要完整保留辨识度的很长测试昵称"
        XCTAssertTrue(author.label.contains(names), "The control must expose the real author.")
        let frame = author.frame
        let time = try XCTUnwrap(app.buttons.matching(identifier: "note.timestamp." + id).allElementsBoundByIndex
            .min { abs($0.frame.midY - frame.midY) < abs($1.frame.midY - frame.midY) })
        let second = time.frame
        let body = try XCTUnwrap(app.descendants(matching: .any).matching(identifier: "note.open." + id).allElementsBoundByIndex
            .min { abs($0.frame.midY - frame.midY) < abs($1.frame.midY - frame.midY) })
        let column = body.frame
        if phase == "accessibility" {
            XCTAssertGreaterThanOrEqual(second.minY, frame.maxY - 0.5)
            XCTAssertEqual(frame.minX, column.minX, accuracy: 1)
            XCTAssertEqual(second.minX, column.minX, accuracy: 1)
            XCTAssertEqual(frame.width, column.width, accuracy: 1)
            XCTAssertEqual(second.width, column.width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(frame.width, 150)
        } else {
            XCTAssertEqual(frame.midY, second.midY, accuracy: 1)
            XCTAssertLessThanOrEqual(frame.maxX, second.minX + 0.5)
        }
        XCTAssertGreaterThanOrEqual(frame.height, 43.5)
        XCTAssertGreaterThanOrEqual(second.height, 43.5)
        let prefix = phase + (guest ? "-guest" : "")
        let crop = XCTAttachment(screenshot: author.screenshot())
        crop.name = prefix + "-author-crop"; crop.lifetime = .keepAlways; add(crop)
        capture(app, prefix + "-header")
        author.tap()
        XCTAssertTrue(app.navigationBars["个人主页"].waitForExistence(timeout: 10))
        app.navigationBars["个人主页"].buttons.firstMatch.tap()
        let target = reveal(app, "note.timestamp." + id)
        target.tap()
        XCTAssertTrue(app.navigationBars["帖子"].waitForExistence(timeout: 10))
        app.navigationBars["帖子"].buttons.firstMatch.tap()
        XCTAssertTrue(reveal(app, "note.author." + id).isHittable)
        return ["expectedName": names, "AXName": author.label, "authorWidth": frame.width, "authorMinY": frame.minY,
                "authorMaxY": frame.maxY, "timeMinY": second.minY, "timeMaxY": second.maxY, "timeWidth": second.width,
                "columnWidth": column.width, "navigation": ["个人主页", "帖子", "原时间线"]]
    }
    private func capture(_ app: XCUIApplication, _ label: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = label; image.lifetime = .keepAlways; add(image)
    }
    private func reveal(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(identifier: id)
        let timelineScroll = app.scrollViews["timeline.scroll"]
        let scroll = timelineScroll.exists ? timelineScroll : app.scrollViews.firstMatch
        // A repost and the original can expose controls for the same note ID.
        // Search only the visible reading area, including the taller accessible selector.
        for _ in 0..<32 {
            let header = [app.buttons["home.more"], app.buttons["timeline.global"]]
                .filter { $0.exists }.map { $0.frame.maxY }.max() ?? scroll.frame.minY
            let upper = max(scroll.frame.minY, header) + 6
            let lower = (app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY) - 12
            let controls = matches.allElementsBoundByIndex.filter { !$0.frame.isEmpty }
            if let visible = controls.first(where: {
                $0.frame.midY >= upper && $0.frame.midY <= lower && $0.isHittable
            }) { return visible }
            let center = (upper + lower) / 2
            let nearest = controls.min { abs($0.frame.midY - center) < abs($1.frame.midY - center) }
            let distance = min(110, max(48, abs((nearest?.frame.midY ?? lower) - center)))
            let dy = (nearest?.frame.midY ?? lower) < center ? distance : -distance
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.midX, dy: center))
            start.press(forDuration: 0.12, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)),
                        withVelocity: .slow, thenHoldForDuration: 0.22)
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "unreachable-" + id
        tree.lifetime = .keepAlways
        add(tree)
        XCTFail("Could not reach control " + id)
        return matches.firstMatch
    }

}
