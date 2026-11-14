import XCTest
import UIKit

final class PublicVideoPosterUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func verify(_ mode: String, expected: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--timeline-align", "--gif-preview", "--video-poster-fixture=" + mode]
        app.launch(); puboSelectTab(app, "世界圈")
        let poster = app.descendants(matching: .any).matching(identifier: "media.poster.posterfixture").firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 15))
        let loaded = NSPredicate(format: "value == %@", expected)
        expectation(for: loaded, evaluatedWith: poster)
        waitForExpectations(timeout: 15)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "video-poster-" + mode; image.lifetime = .keepAlways; add(image)
        if expected == "video-frame" {
            guard let pixels = poster.screenshot().image.cgImage else { XCTFail("Missing poster pixels"); return }
            let width = 40, height = 40
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let redFraction: Double = bytes.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
                context.draw(pixels, in: CGRect(x: 0, y: 0, width: width, height: height))
                let values = buffer.bindMemory(to: UInt8.self)
                let red = stride(from: 0, to: values.count, by: 4).filter {
                    values[$0] > 170 && values[$0 + 1] < 80 && values[$0 + 2] < 80
                }.count
                return Double(red) / Double(width * height)
            }
            XCTAssertGreaterThan(redFraction, 0.35, "Decoder-ready alone is insufficient: the red first frame must be visibly rendered")
        }
        app.terminate()
    }
    func testUntrustedSyntheticVideoFailsClosed() { verify("untrusted", expected: "unavailable") }
    func testMissingThumbnailDecodesBundledVideo() { verify("missing", expected: "video-frame") }
    func testBrokenThumbnailDecodesBundledVideo() { verify("broken", expected: "video-frame") }
    func testServerThumbnailAvoidsVideoDecoder() { verify("thumbnail", expected: "thumbnail") }
}
