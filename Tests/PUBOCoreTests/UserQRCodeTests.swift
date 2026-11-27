import XCTest
#if canImport(CoreImage) && canImport(CoreGraphics)
import CoreGraphics
import CoreImage
#endif
@testable import PUBOCore

final class UserQRCodeTests: XCTestCase {
    func testExistingH5UserCode() {
        XCTAssertEqual(UserQRCode.userID(from: "https://bolubo.com/users/abc123"), "abc123")
        XCTAssertEqual(UserQRCode.userID(from: "https://bolubo.com:443/users/abc_123-xyz"), "abc_123-xyz")
    }
    func testRejectsNonUserAndUntrustedCodes() {
        for value in ["https://evil.com/users/abc", "https://bolubo.com.evil.com/users/abc", "http://bolubo.com/users/abc", "https://bolubo.com@evil.com/users/abc", "https://evil@bolubo.com/users/abc", "https://bolubo.com:444/users/abc", "https://bolubo.com/users/", "https://bolubo.com/users/abc/", "https://bolubo.com/users/../login", "https://bolubo.com/users/%61bc", "https://bolubo.com/users/abc?token=x", "https://bolubo.com/users/abc#x", "https://bolubo.com/login", "https://bolubo.com/@abc", "pubonative://login", " abc ", "https://bolubo.com/users/名字"] {
            XCTAssertNil(UserQRCode.userID(from: value), value)
        }
    }
    func testGeneratesValidH5UserCodeURLAndRoundTrips() {
        for id in ["abc123", "abc_123-xyz", "syntheticself", "syntheticuser0001"] {
            let url = UserQRCode.url(forUserID: id)
            XCTAssertEqual(url?.absoluteString, "https://bolubo.com/users/\(id)")
            XCTAssertEqual(url.flatMap { UserQRCode.userID(from: $0.absoluteString) }, id)
        }
    }
    func testRejectsInvalidUserIDsWhenGeneratingURL() {
        for bad in ["", " ", "abc/def", "../login", "abc?x=1", "abc#x", "名字", String(repeating: "a", count: 129)] {
            XCTAssertNil(UserQRCode.url(forUserID: bad), bad)
        }
    }
    func testFormatsH5DisplayHandle() {
        XCTAssertEqual(UserQRCode.displayHandle(username: "fixture"), "@fixture@bolubo.com")
        XCTAssertEqual(UserQRCode.displayHandle(username: "@fixture", host: ""), "@fixture@bolubo.com")
        XCTAssertEqual(UserQRCode.displayHandle(username: "alice", host: "example.social"), "@alice@example.social")
        XCTAssertNil(UserQRCode.displayHandle(username: "   "))
        XCTAssertNil(UserQRCode.displayHandle(username: nil))
    }

#if canImport(CoreImage) && canImport(CoreGraphics)
    func testMatrixTrimsQuietZoneAndAlignsAllThreeFinders() throws {
        for id in ["syntheticself", "syntheticuser0001", "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"] {
            let url = try XCTUnwrap(UserQRCode.url(forUserID: id))
            let matrix = try XCTUnwrap(UserQRCodeRenderer.qrMatrix(for: url.absoluteString))
            let n = matrix.count
            XCTAssertGreaterThanOrEqual(n, 21)
            XCTAssertEqual((n - 21) % 4, 0, "Trimmed QR dimension must satisfy ISO 21 + 4*(v-1), got \(n)")
            XCTAssertTrue(matrix[0].contains(true), "Top row must contain dark finder modules (no untrimmed quiet zone)")
            XCTAssertTrue(matrix[n - 1].contains(true), "Bottom row must contain dark finder modules (no untrimmed quiet zone)")
            XCTAssertEqual(UserQRCodeRenderer.finderScore(matrix, col: 0, row: 0), 49)
            XCTAssertEqual(UserQRCodeRenderer.finderScore(matrix, col: n - 7, row: 0), 49)
            XCTAssertEqual(UserQRCodeRenderer.finderScore(matrix, col: 0, row: n - 7), 49)
            XCTAssertLessThan(UserQRCodeRenderer.finderScore(matrix, col: n - 7, row: n - 7), 49)
        }
    }

    func testRenderedStyledQRImageDecodesWithAppleCIDetectorAcrossSizesAndThemes() throws {
        let detector = try XCTUnwrap(CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ))

        for id in ["syntheticself", "syntheticuser0001", "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"] {
            let url = try XCTUnwrap(UserQRCode.url(forUserID: id))
            for pixelSize in [488, 732, 900] {
                let image = try XCTUnwrap(UserQRCodeRenderer.renderCGImage(for: url, pixelSize: pixelSize))
                let decoded = detector.features(in: CIImage(cgImage: image))
                    .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
                XCTAssertTrue(
                    decoded.contains(url.absoluteString),
                    "CIDetector failed on \(pixelSize)px styled QR for \(id); got \(decoded)"
                )
            }

            // Composite onto full 1320x2868 light and dark screens to mirror real iPhone Pro Max screenshots.
            let card = try XCTUnwrap(UserQRCodeRenderer.renderCGImage(for: url, pixelSize: 732))
            let themes: [(String, (CGFloat, CGFloat, CGFloat))] = [
                ("light", (0.976, 0.976, 0.976)),
                ("dark", (0.051, 0.063, 0.055))
            ]
            for (theme, bg) in themes {
                let screen = try XCTUnwrap(compositeCard(card, onCanvasWidth: 1320, height: 2868, rgb: bg))
                let decoded = detector.features(in: CIImage(cgImage: screen))
                    .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
                XCTAssertTrue(
                    decoded.contains(url.absoluteString),
                    "CIDetector failed on full \(theme) screen for \(id); got \(decoded)"
                )
            }
        }
    }

    private func compositeCard(_ card: CGImage, onCanvasWidth width: Int, height: Int, rgb: (CGFloat, CGFloat, CGFloat)) -> CGImage? {
        guard let cg = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        cg.setFillColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let x = (width - card.width) / 2
        let y = (height - card.height) / 2
        cg.draw(card, in: CGRect(x: x, y: y, width: card.width, height: card.height))
        return cg.makeImage()
    }
#endif
}
