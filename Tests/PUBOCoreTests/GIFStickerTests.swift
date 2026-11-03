import XCTest
import ImageIO
import CoreGraphics
@testable import PUBOCore

final class GIFStickerTests: XCTestCase {
    private func fixture(noisy: Bool = false, loop: Int = 1) throws -> Data {
        let count = noisy ? 16 : 3, size = 96, data = NSMutableData()
        let output = try XCTUnwrap(CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, count, nil))
        CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loop]] as CFDictionary)
        var seed: UInt32 = 12345
        for frame in 0..<count {
            var pixels = [UInt8](repeating: 255, count: size * size * 4)
            for index in stride(from: 0, to: pixels.count, by: 4) {
                seed = seed &* 1664525 &+ 1013904223
                pixels[index] = noisy ? UInt8(truncatingIfNeeded: seed >> 24) : UInt8(frame * 50)
                pixels[index + 1] = noisy ? UInt8(truncatingIfNeeded: seed >> 16) : 80
                pixels[index + 2] = noisy ? UInt8(truncatingIfNeeded: seed >> 8) : 160
            }
            let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
            let image = try XCTUnwrap(CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            CGImageDestinationAddImage(output, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: [0.04, 0.2, 0.08][frame % 3]]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(output)); return data as Data
    }
    private func timing(_ data: Data) throws -> (Int, Double, Int?) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil)), count = CGImageSourceGetCount(source)
        let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let loop = ((props?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue
        var total = 0.0
        for i in 0..<count {
            let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any], gif = p?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            total += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0
        }
        return (count, total, loop)
    }
    func testSmallGIFIsPreservedByteForByte() async throws {
        let data = try fixture(), prepared = try await GIFStickerCodec.prepare(data)
        XCTAssertLessThan(data.count, 100_000); XCTAssertEqual(prepared.data, data); XCTAssertFalse(prepared.wasCompressed)
        XCTAssertEqual(prepared.sourceSHA256, GIFStickerCodec.digest(data))
    }
    func testCompressionKeepsAnimationDurationAndFiniteLoopUnderHardLimit() async throws {
        let data = try fixture(noisy: true), before = try timing(data)
        XCTAssertGreaterThan(data.count, 100_000)
        let result = try await GIFStickerCodec.prepare(data), after = try timing(result.data)
        XCTAssertTrue(result.wasCompressed); XCTAssertLessThanOrEqual(result.data.count, 100_000)
        XCTAssertGreaterThan(after.0, 1); XCTAssertEqual(before.1, after.1, accuracy: 0.03); XCTAssertEqual(after.2, before.2)
    }
    func testInvalidAndOversizeInputsAreRejected() async {
        for value in [Data(), Data("GIF89a broken".utf8), Data(repeating: 0, count: GIFStickerCodec.inputLimit + 1)] {
            do { _ = try await GIFStickerCodec.prepare(value); XCTFail("Invalid input accepted") } catch { XCTAssertTrue(error is GIFStickerError) }
        }
    }
    func testCancelledCompressionDoesNotReturnASticker() async throws {
        let data = try fixture(noisy: true)
        let task = Task { try await GIFStickerCodec.prepare(data) }; task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled compression returned output") } catch { XCTAssertTrue(error is CancellationError) }
    }
    @MainActor func testVaultDeduplicatesPersistsAndIsolatesAccounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pubo-gif-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try GIFStickerVault(root: root), prepared = try await GIFStickerCodec.prepare(fixture())
        let first = try vault.add(prepared, account: "accountA")
        XCTAssertTrue(first.inserted); XCTAssertFalse(try vault.add(prepared, account: "accountA").inserted)
        XCTAssertTrue(try vault.list(account: "accountB").isEmpty)
        XCTAssertThrowsError(try vault.data(first.sticker, account: "accountB"))
        let reopened = try GIFStickerVault(root: root)
        XCTAssertEqual(try reopened.data(first.sticker, account: "accountA"), prepared.data)
        _ = try reopened.add(prepared, account: "accountB"); try reopened.clear(account: "accountA")
        XCTAssertTrue(try reopened.list(account: "accountA").isEmpty); XCTAssertEqual(try reopened.list(account: "accountB").count, 1)
        let second = try XCTUnwrap(reopened.list(account: "accountB").first); try reopened.remove(second, account: "accountB")
        XCTAssertTrue(try reopened.list(account: "accountB").isEmpty)
    }
    @MainActor func testCorruptBytesAndPathTraversalAreRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pubo-gif-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try GIFStickerVault(root: root), prepared = try await GIFStickerCodec.prepare(fixture())
        let entry = try vault.add(prepared, account: "accountA").sticker
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("accountA").appendingPathComponent(entry.id + ".gif"))
        XCTAssertThrowsError(try vault.data(entry, account: "accountA"))
        XCTAssertThrowsError(try vault.list(account: "../other")); XCTAssertThrowsError(try vault.clear(account: ".."))
    }
}
