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
        let values: [String: Any] = ["phase": phase, "fixture": id, "bodyText": firstText,
                                     "bodyWidth": bodyRect.width, "bodyHeight": bodyRect.height,
                                     "deviceWidth": app.frame.width, "deviceHeight": app.frame.height,
                                     "actions": geometry, "arguments": app.launchArguments]
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = phase + "-geometry.json"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func capture(_ app: XCUIApplication, _ label: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = label; image.lifetime = .keepAlways; add(image)
    }
    private func reveal(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(identifier: id)
        let scroll = app.scrollViews["timeline.scroll"]
        // A repost and the original can expose controls for the same note ID.
        // Search only the visible reading area, including the taller accessible selector.
        for _ in 0..<24 {
            let header = [app.buttons["home.more"], app.buttons["timeline.global"]]
                .filter { $0.exists }.map { $0.frame.maxY }.max() ?? scroll.frame.minY
            let upper = max(scroll.frame.minY, header) + 6
            let lower = app.tabBars.firstMatch.frame.minY - 12
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
