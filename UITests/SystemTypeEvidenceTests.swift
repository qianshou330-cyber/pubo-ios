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
        let author = reveal(app, "note.author." + id)
        let authorInkHeight = try inkHeight(author, label: phase + "-author-crop")
        capture(app, phase + "-header")
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
        let guestAuthor = reveal(app, "note.author." + id)
        let guestInkHeight = try inkHeight(guestAuthor, label: phase + "-guest-author-crop")
        capture(app, phase + "-guest-header")
        let values: [String: Any] = ["phase": phase, "fixture": id, "bodyText": firstText,
                                     "selectorVertical": vertical, "selectorCenters": selectorCenters,
                                     "authorInkHeightPt": authorInkHeight, "guestAuthorInkHeightPt": guestInkHeight,
                                     "bodyWidth": bodyRect.width, "bodyHeight": bodyRect.height,
                                     "deviceWidth": signedDimensions.width, "deviceHeight": signedDimensions.height,
                                     "actions": geometry, "arguments": signedArguments]
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = phase + "-geometry.json"; attachment.lifetime = .keepAlways; add(attachment)
    }
    // Measure the actual first glyphs in the nickname button, before its account and badges.
    private func inkHeight(_ element: XCUIElement, label: String) throws -> CGFloat {
        let shot = element.screenshot()
        let attachment = XCTAttachment(screenshot: shot); attachment.name = label
        attachment.lifetime = .keepAlways; add(attachment)
        let cg = try XCTUnwrap(shot.image.cgImage)
        let width = cg.width, height = cg.height
        let scale = CGFloat(width) / element.frame.width
        let stop = min(width - 1, Int(45 * scale))
        let start = max(1, Int(scale))
        XCTAssertGreaterThan(stop, start)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        try rgba.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        let rows = (0..<height).filter { y in
            (start..<stop).contains { x in
                let i = 4 * (y * width + x)
                return rgba[i+3] > 200 && max(rgba[i], max(rgba[i+1], rgba[i+2])) < 155
            }
        }
        let first = try XCTUnwrap(rows.first, label), last = try XCTUnwrap(rows.last, label)
        return CGFloat(last - first + 1) / scale
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
