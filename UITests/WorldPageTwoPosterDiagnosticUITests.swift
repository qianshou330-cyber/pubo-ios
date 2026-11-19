#if DEBUG && PUBO_PAGE2_POSTER_PROBE
import XCTest
import UIKit

/// Opt-in, synthetic-only observation. No frame-rate, timing or device acceptance.
final class WorldPageTwoPosterDiagnosticUITests: XCTestCase {
    private var app: XCUIApplication?
    private var stage = "not-launched"
    private var observations: [[String: Any]] = []
    private var summary: [String: Any] = ["result": "UNAVAILABLE", "latencyPointEstimate": "UNAVAILABLE"]
    private var clock: Double { ProcessInfo.processInfo.systemUptime }

    override func setUpWithError() throws { continueAfterFailure = false }
    private func attach(_ shot: XCUIScreenshot, _ name: String) {
        let a = XCTAttachment(screenshot: shot); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    override func tearDownWithError() throws {
        summary["lastStage"] = stage; summary["observations"] = observations
        summary["measuredHitches"] = "UNAVAILABLE"; summary["physicalDeviceProof"] = false
        summary["scope"] = "Observation bracket, not a continuous capture, decoder-time estimate or SLA."
        if JSONSerialization.isValidJSONObject(summary),
           let bytes = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            let att = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
            att.name = "page2-observations"; att.lifetime = .keepAlways; add(att)
        }
        if let app, app.state == .runningForeground { attach(app.screenshot(), "page2-final-" + stage) }
        app?.terminate(); app = nil
        try super.tearDownWithError()
    }

    /// Visible crop in application-point (top-left) coordinates; exclude fixed chrome.
    private func clip(_ app: XCUIApplication, _ poster: XCUIElement) -> CGRect? {
        guard poster.exists, poster.isHittable else { return nil }
        let scroll = app.scrollViews["timeline.scroll"].frame
        let header = app.buttons["home.more"].frame
        let bar = app.descendants(matching: .any).matching(identifier: "app.tabBar").firstMatch.frame
        let raw = poster.frame
        guard [scroll, header, bar, raw].allSatisfy({ r in
            [r.minX, r.minY, r.width, r.height].allSatisfy { $0.isFinite } && r.width > 0 && r.height > 0
        }) else { return nil }
        let top = max(scroll.minY, header.maxY + 4), bottom = min(scroll.maxY, bar.minY - 4)
        guard bottom > top else { return nil }
        let viewport = CGRect(x: scroll.minX, y: top, width: scroll.width, height: bottom - top).intersection(app.frame)
        let r = raw.intersection(viewport)
        // An identification requirement for the crop, not a scrolling or time threshold.
        guard !r.isNull, r.width >= 0.8 * raw.width, r.height >= 0.65 * raw.height,
              r.width >= 56, r.height >= 40 else { return nil }
        return r.insetBy(dx: 4, dy: 4)
    }

    /// Crop the actual whole-app screenshot, not an XCUI element snapshot (which may contain offscreen content).
    private func redFraction(_ shot: XCUIScreenshot, in pointRect: CGRect, appFrame: CGRect) -> Double? {
        let img = shot.image
        guard img.imageOrientation == .up, let cg = img.cgImage, appFrame.width > 0, appFrame.height > 0,
              appFrame.contains(pointRect) else { return nil }
        let sx = CGFloat(cg.width) / appFrame.width, sy = CGFloat(cg.height) / appFrame.height
        guard sx > 0, sy > 0, abs(sx - sy) < 0.02 else { return nil }
        // Round inward, never include a pixel outside the verified screen region.
        let x = ceil((pointRect.minX - appFrame.minX) * sx), y = ceil((pointRect.minY - appFrame.minY) * sy)
        let right = floor((pointRect.maxX - appFrame.minX) * sx), bottom = floor((pointRect.maxY - appFrame.minY) * sy)
        guard right > x, bottom > y, let crop = cg.cropping(to: CGRect(x: x, y: y, width: right-x, height: bottom-y)) else { return nil }
        let n = 48
        var pixels = [UInt8](repeating: 0, count: n*n*4)
        return pixels.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) -> Double? in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n*4,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(n), height: CGFloat(n)))
            let b = buf.bindMemory(to: UInt8.self)
            let hits = stride(from: 0, to: b.count, by: 4).filter { b[$0] > 170 && b[$0+1] < 80 && b[$0+2] < 80 }
            return Double(hits.count) / Double(n*n)
        }
    }
    private func nearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        zip([a.minX,a.minY,a.maxX,a.maxY], [b.minX,b.minY,b.maxX,b.maxY]).allSatisfy { abs($0.0 - $0.1) <= 0.5 }
    }

    func testNativeSecondPagePosterVisiblePixels() {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--ui-testing", "--timeline-align", "--gif-preview", "--world-page2-poster"]
        stage = "launch-world"; app.launch(); puboSelectTab(app, "世界圈")
        let scroll = app.scrollViews["timeline.scroll"]
        let newest = app.descendants(matching: .any).matching(identifier: "note.open.at4tltest0025").firstMatch
        let poster = app.buttons["media.open.worldpage2poster0001"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10)); XCTAssertTrue(newest.waitForExistence(timeout: 10))
        stage = "establish-absent-baseline"
        let baselineStart = clock
        guard newest.isHittable, !poster.exists else { XCTFail("No verified initial top/absent target; no bound."); return }
        attach(app.screenshot(), "page2-newest-target-absent")
        let baselineEnd = clock
        summary["baselineAbsentBracketUptime"] = [baselineStart, baselineEnd]
        var drags = 0, eligibleCaptures = 0
        // Real forward-only gestures, no scrollTo or forced backend load. The last
        // seed row is the target; a strict observation guard is not an SLA.
        while drags <= 32 && eligibleCaptures < 12 {
            stage = "seek-eligible-viewport"
            guard let r0 = clip(app, poster) else {
                if eligibleCaptures > 0 { XCTFail("Lost target after eligible sample; no continuous exposure claimed."); return }
                if drags == 32 { break }
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
                start.press(forDuration: 0.05, thenDragTo: end); drags += 1
                continue
            }
            stage = "observe-visible-screenshot"; eligibleCaptures += 1
            let pre = poster.value as? String ?? "unknown"
            let appFrame = app.frame, captureStart = clock, shot = app.screenshot(), captureEnd = clock
            guard let r1 = clip(app, poster), nearlyEqual(r0, r1), nearlyEqual(appFrame, app.frame),
                  let red = redFraction(shot, in: r0.intersection(r1), appFrame: appFrame) else {
                attach(shot, "page2-geometry-unresolved-" + String(eligibleCaptures))
                observations.append(["index":eligibleCaptures, "result":"UNRESOLVED_GEOMETRY", "clock":[captureStart,captureEnd]])
                continue
            }
            let post = poster.value as? String ?? "unknown"
            let rendered = red > 0.35
            let ready = pre == post && ["video-frame", "cached"].contains(post)
            observations.append(["index":eligibleCaptures, "drags":drags, "shotBracketUptime":[captureStart,captureEnd],
                                 "cropPoints":NSCoder.string(for: r0.intersection(r1)), "appFramePoints":NSCoder.string(for: appFrame),
                                 "preState":pre, "postState":post, "redFraction":red, "pixelSignatureSeen":rendered])
            attach(shot, "page2-eligible-" + String(eligibleCaptures))
            if ready && rendered {
                guard drags > 0, captureEnd >= baselineStart else { XCTFail("Missing native gesture or invalid bracket"); return }
                summary["result"] = "OBSERVED_VISIBLE_RED_FIXTURE"
                summary["visibleAtOrBeforeUptime"] = captureEnd
                // Some exposure occurred after the verified absent baseline and by this shot.
                // Could already have been rendered when it entered; onset is not continuously observed.
                summary["absentBaselineToRedUpperBoundSeconds"] = captureEnd - baselineStart
                summary["viewportToVisibleRedConservativeBoundsSeconds"] = [0.0, captureEnd - baselineStart]
                summary["lowerEndpointMeaning"] = "Zero is possible, not a measured latency."
                if let first = observations.first?["pixelSignatureSeen"] as? Bool {
                    summary["firstEligibleSampleAlreadyRed"] = first
                } else { summary["firstEligibleSampleAlreadyRed"] = "UNAVAILABLE" }
                summary["drags"] = drags
                stage = "observed-not-speed-certified"
                return
            }
        }
        stage = "no-qualified-red-observation"
        XCTFail("No conclusive visible native red crop within bounded diagnostic sampling; latency UNAVAILABLE.")
    }
}
#endif
