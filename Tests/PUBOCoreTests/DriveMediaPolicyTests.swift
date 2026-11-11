import XCTest
@testable import PUBOCore

final class DriveMediaPolicyTests: XCTestCase {
    func testSensitiveFilesRequireExplicitDisclosure() {
        XCTAssertTrue(DriveMediaPolicy.requiresConfirmation(isSensitive: true))
        XCTAssertFalse(DriveMediaPolicy.requiresConfirmation(isSensitive: false))
    }
    func testImageEligibilityIsIndependentOfSensitivity() {
        for mime in ["image/png", "image/gif", "image/webp"] {
            XCTAssertTrue(DriveMediaPolicy.canSelect(mime: mime, imagesOnly: true))
        }
        for mime in ["", "video/mp4", "application/pdf", "image-not-a-mime"] {
            XCTAssertFalse(DriveMediaPolicy.canSelect(mime: mime, imagesOnly: true))
            XCTAssertTrue(DriveMediaPolicy.canSelect(mime: mime, imagesOnly: false))
        }
    }
}
