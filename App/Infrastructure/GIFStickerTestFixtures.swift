#if DEBUG
import Foundation
import CoreGraphics
import ImageIO

extension GIFTestFixtures {
    static var compressible: Data {
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, 16, nil) else { return Data() }
        CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        var seed: UInt32 = 12345
        for _ in 0..<16 {
            var pixels = [UInt8](repeating: 255, count: 96 * 96 * 4)
            for index in stride(from: 0, to: pixels.count, by: 4) {
                seed = seed &* 1664525 &+ 1013904223
                pixels[index] = UInt8(truncatingIfNeeded: seed >> 24); pixels[index + 1] = UInt8(truncatingIfNeeded: seed >> 16); pixels[index + 2] = UInt8(truncatingIfNeeded: seed >> 8)
            }
            guard let provider = CGDataProvider(data: Data(pixels) as CFData), let image = CGImage(width: 96, height: 96, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 96 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return Data() }
            CGImageDestinationAddImage(output, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(output) else { return Data() }; return data as Data
    }
}
#endif
