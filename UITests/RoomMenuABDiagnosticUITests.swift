#if DEBUG && PUBO_ROOM_MENU_AB_DIAGNOSTIC
import XCTest

/// Synthetic comparison only. The required ChatAlignmentUITests remains unchanged.
final class RoomMenuABDiagnosticUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func test01OwnText() throws { try observe("text") }
    func test02OwnBubblePadding() throws { try observe("padding") }

    private func addEvidence(_ item: XCTAttachment, _ name: String) {
        item.name = name
        item.lifetime = .keepAlways
        add(item)
    }

    private func observe(_ arm: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--social-align", "--chat-align"]
        if app.state != .notRunning { app.terminate() }
        app.launch()
        defer { app.terminate() }

        // Match the ordinary light-room test's launch, navigation, fixture and menu query.
        guard puboTab(app, "消息").waitForExistence(timeout: 15) else {
            return XCTFail("ROOM_MENU_AB_PRECONDITION: messages tab")
        }
        puboSelectTab(app, "消息")
        guard app.buttons["messages.add"].waitForExistence(timeout: 8) else {
            return XCTFail("ROOM_MENU_AB_PRECONDITION: messages screen")
        }
        let row = app.buttons["conversation.room:socialroom"]
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        guard row.waitForExistence(timeout: 8), row.isHittable else {
            return XCTFail("ROOM_MENU_AB_PRECONDITION: room fixture")
        }
        row.tap()
        let input = app.textViews["room.input"]
        let own = app.descendants(matching: .any).matching(identifier: "room.bubble.room0002").firstMatch
        guard input.waitForExistence(timeout: 8), own.waitForExistence(timeout: 6) else {
            return XCTFail("ROOM_MENU_AB_PRECONDITION: fixture input or own message")
        }
        let ownText = own.textViews.firstMatch
        let overflow = app.buttons["room.menu.room0002"]
        let timeline = app.scrollViews["room.timeline"]
        let window = app.windows.firstMatch
        let title = "删除消息"
        let delete = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND (elementType == %d OR elementType == %d)",
            title, XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue
        )).firstMatch
        let expectedBody = "大家好，很高兴认识你们。"
        guard ownText.exists, ownText.isHittable,
              ownText.label == expectedBody || (ownText.value as? String) == expectedBody,
              overflow.exists, timeline.exists, window.exists, !app.keyboards.firstMatch.exists else {
            return XCTFail("ROOM_MENU_AB_PRECONDITION: visible exact text/room geometry or keyboard")
        }
        let text = ownText.frame
        let menu = overflow.frame
        let view = timeline.frame
        let bounds = window.frame
        let composer = input.frame
        // RoomChatView pads the bubble's content by 12pt horizontally. Use its
        // midpoint on the left of the own message (away from the right-hand tail).
        // The bubble AX wrapper in C82 collapses to the text rect; it is not the
        // bubble background. Check the known padding lane against the sibling menu.
        let center = CGPoint(x: text.midX, y: text.midY)
        let padding = CGPoint(x: text.minX - 6, y: text.midY)
        let rects = [text, menu, view, bounds, composer]
        guard rects.allSatisfy({ !$0.isEmpty && !$0.isInfinite &&
                               [$0.minX, $0.minY, $0.maxX, $0.maxY].allSatisfy(\.isFinite) }),
              bounds == CGRect(x: 0, y: 0, width: 402, height: 874),
              bounds.contains(text), view.contains(center), view.contains(padding),
              bounds.contains(padding), padding.y < composer.minY,
              menu.maxX + 2 <= padding.x, !text.contains(padding),
              !menu.contains(center), !menu.contains(padding) else {
            return XCTFail("ROOM_MENU_AB_PRECONDITION: unsafe or nonstandard padding geometry")
        }

        func labels(_ tree: XCUIElementSnapshot) -> [String] {
            let menuNodes = puboSnapshotDescendants(tree).filter { node in
                node.elementType == .button || node.elementType == .menuItem
            }
            let limited = Set([title, "复制", "拷贝", "举报", "查找", "翻译", "全选"])
            return Set(menuNodes.map(\.label).filter { limited.contains($0) }).sorted()
        }
        let pre = try app.snapshot()
        let preLabels = labels(pre)
        guard !preLabels.contains(title), !delete.exists else {
            return XCTFail("ROOM_MENU_AB_PRECONDITION: menu already visible before gesture")
        }
        addEvidence(XCTAttachment(string: String(describing: pre.dictionaryRepresentation)), "room-menu-ab-\(arm)-pre-ax")
        addEvidence(XCTAttachment(screenshot: XCUIScreen.main.screenshot()), "room-menu-ab-\(arm)-pre-screen")

        switch arm {
        case "text": ownText.press(forDuration: 1)
        case "padding":
            window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: padding.x - bounds.minX, dy: padding.y - bounds.minY))
                .press(forDuration: 1)
        default: return XCTFail("ROOM_MENU_AB_PRECONDITION: unknown arm")
        }
        // Same five-second exact menu-item query as the original test. Do not tap
        // any action, retry the press, or reinterpret AX-empty as a UI pass.
        let found = delete.waitForExistence(timeout: 5)
        let post = try app.snapshot()
        let postLabels = labels(post)
        addEvidence(XCTAttachment(string: String(describing: post.dictionaryRepresentation)), "room-menu-ab-\(arm)-post-ax")
        addEvidence(XCTAttachment(screenshot: XCUIScreen.main.screenshot()), "room-menu-ab-\(arm)-post-screen")
        let result: [String: Any] = [
            "schema": 1, "arm": arm, "theme": "light", "fixture": "socialroom/room0002",
            "gesture": arm == "text" ? "ownText.press" : "bubble-padding.press",
            "pressCount": 1, "pressSeconds": 1, "deleteQueryTimeoutSeconds": 5,
            "deleteQueryFound": found, "preLabels": preLabels, "postLabels": postLabels,
            "window": components(bounds), "text": components(text), "overflow": components(menu),
            "timeline": components(view), "composerInput": components(composer),
            "intendedPoint": arm == "text" ? [Double(center.x), Double(center.y)] : [Double(padding.x), Double(padding.y)],
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        addEvidence(XCTAttachment(string: String(decoding: json, as: UTF8.self)), "room-menu-ab-\(arm)-receipt")
    }

    private func components(_ rect: CGRect) -> [Double] {
        [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
    }
}
#endif
