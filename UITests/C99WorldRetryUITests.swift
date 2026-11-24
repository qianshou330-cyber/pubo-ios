import XCTest
import PUBONotify

private struct C99ProbeFailure: Error { let reason: String; init(_ reason: String) { self.reason = reason } }

/// The runner creates BOTH names before launching the app, then never writes the phase again.
private final class C99WorldLatch {
    let nonce = UUID().uuidString
    var receipt: String { String(nonce.replacingOccurrences(of: "-", with: "").lowercased().dropLast()) + "5" }
    private var tokens: [String: Int32] = [:]
    init() throws {
        do {
            for side in ["phase", "release"] {
                var token: Int32 = 0
                guard notify_register_check("com.bolubo.fixture.c99world." + nonce + "." + side, &token) == NOTIFY_STATUS_OK
                else { throw C99ProbeFailure("register " + side) }
                tokens[side] = token
                guard notify_set_state(token, 0) == NOTIFY_STATUS_OK else { throw C99ProbeFailure("init " + side) }
            }
        } catch { close(); throw error }
    }
    private func close() { for token in tokens.values { notify_cancel(token) }; tokens.removeAll() }
    deinit { close() }
    func expect(_ stage: UInt64) throws {
        var got: UInt64 = 0
        guard let token = tokens["phase"], notify_get_state(token, &got) == NOTIFY_STATUS_OK, got == stage
        else { throw C99ProbeFailure("transport stage expected \(stage), read \(got)") }
    }
    func release() throws {
        try expect(2)
        guard let token = tokens["release"], notify_set_state(token, 1) == NOTIFY_STATUS_OK
        else { throw C99ProbeFailure("release") }
    }
}

final class C99WorldRetryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private enum Stage: UInt64 { case failed = 1, held, recovered }
    private func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw C99ProbeFailure(message) }
    }

    /// Every evaluation consumes ONE fresh immutable whole-app snapshot. The header and scroll are
    /// siblings; row/status/Retry checks belong exclusively to this scroll, not a hidden route.
    private func read(_ app: XCUIApplication, _ latch: C99WorldLatch, _ stage: Stage) throws {
        try latch.expect(stage.rawValue)
        let all = puboSnapshotDescendants(try app.snapshot())
        func selected(_ id: String, _ label: String) -> Bool {
            let buttons = all.filter { $0.elementType == .button && $0.identifier == id }
            return buttons.count == 1 && buttons[0].isSelected && buttons[0].label == label
        }
        try check(selected("app.tab.world", "世界圈"), "expected selected World tab")
        try check(selected("world.recommended", "推荐"), "expected selected Recommended feed")
        let following = all.filter { $0.elementType == .button && $0.identifier == "world.following" }
        try check(following.count == 1 && !following[0].isSelected, "unexpected Following selection")
        let scrolls = all.filter { $0.elementType == .scrollView && $0.identifier == "timeline.scroll" }
        try check(scrolls.count == 1, "expected a single timeline.scroll")
        let inside = puboSnapshotDescendants(scrolls[0])
        let viewport = all[0].frame.intersection(scrolls[0].frame)
        func visible(_ node: XCUIElementSnapshot) -> Bool {
            let f = node.frame
            return !f.isNull && !f.isEmpty && viewport.contains(CGPoint(x: f.midX, y: f.midY))
        }
        let retry = inside.filter { $0.elementType == .button && $0.label == "重试" }
        let errors = inside.filter { $0.label.contains("C99_LOCAL_503") }
        let pending = inside.filter { $0.identifier == "timeline.initialRetryLoading" }
        let rows = inside.filter { $0.identifier.hasPrefix("note.open.") }
        let receipt = "note.open." + latch.receipt
        try check(!inside.contains { $0.label == "暂时没有帖子" }, "false empty")
        switch stage {
        case .failed:
            try check(errors.contains(where: visible) && retry.count == 1 && visible(retry[0]) && pending.isEmpty && rows.isEmpty, "missing scoped first 503/Retry or stale content")
        case .held:
            try check(errors.isEmpty && retry.isEmpty && pending.contains(where: visible) && rows.isEmpty, "held request shows old error, rows, or no pending state")
        case .recovered:
            try check(errors.isEmpty && retry.isEmpty && pending.isEmpty && rows.contains { $0.identifier == receipt && visible($0) },
                      "no current-run Local recovery row or stale loading/error")
        }
        try latch.expect(stage.rawValue)
    }
    private func capture(_ app: XCUIApplication, _ latch: C99WorldLatch, _ stage: Stage, _ name: String) throws {
        try read(app, latch, stage)
        let png = app.screenshot().pngRepresentation
        try read(app, latch, stage) // do not attach an image whose boundary checks no longer match
        try check(png.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), "not an original PNG")
        let shot = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        shot.name = "c99-world-" + name; shot.lifetime = .keepAlways; add(shot)
    }

    func testRecommendedRealRetryKeepsSameFeedDuringHeldRead() throws {
        let latch = try C99WorldLatch()
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--c99-world-retry", "--reduce-motion"]
        app.launchEnvironment["PUBO_C99_WORLD_NONCE"] = latch.nonce
        app.launch(); defer { app.terminate() }
        puboSelectTab(app, "世界圈")
        let scroll = app.scrollViews["timeline.scroll"]
        let retry = scroll.buttons.matching(NSPredicate(format: "label == %@", "重试")).firstMatch
        try check(retry.waitForExistence(timeout: 15) && retry.isHittable, "real initial Retry unavailable")
        try capture(app, latch, .failed, "initial-503")
        retry.tap()
        let pending = scroll.descendants(matching: .any).matching(identifier: "timeline.initialRetryLoading").firstMatch
        try check(pending.waitForExistence(timeout: 15), "no pending state")
        // SwiftUI can show progress immediately, before the transport has entered its barrier.
        let held = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (try? latch.expect(2)) != nil }, object: nil)
        try check(XCTWaiter.wait(for: [held], timeout: 10) == .completed, "transport did not observe the real Retry")
        try capture(app, latch, .held, "retry-pending")
        try latch.release()
        let id = "note.open." + latch.receipt
        let row = scroll.descendants(matching: .any).matching(identifier: id).firstMatch
        try check(row.waitForExistence(timeout: 15), "unique recovery row absent")
        try capture(app, latch, .recovered, "retry-restored")
    }
}
