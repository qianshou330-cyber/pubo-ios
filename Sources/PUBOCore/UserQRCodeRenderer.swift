#if canImport(CoreImage) && canImport(CoreGraphics)
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Pure CoreImage + CoreGraphics H5-aligned PUBO QR renderer shared by the iOS app and macOS `swift test` suite.
///
/// Key invariants verified by unit tests (`UserQRCodeTests`) and iOS Simulator UI tests (`FourTabNavigationUITests`):
/// 1. `CIQRCodeGenerator` wraps its output in a 1-module white quiet zone; `qrMatrix(for:)` trims the exact dark-module
///    bounding box (`minRow...maxRow`, `minCol...maxCol`) before drawing finder patterns so finder eyes align 1:1 with the ISO grid.
/// 2. Zero-inset touching rounded modules (`cornerRadius = 0.42 * moduleSize`) match the H5 dot aesthetic without creating
///    inter-module gaps that break high-resolution `CIDetector` or `zbar` scanlines.
/// 3. Quiet zone stays light `#FBFFF0` (4 modules) in both light and dark modes for high contrast against `#455C00` modules.
public enum UserQRCodeRenderer {
    public static let cardBackgroundHex: UInt32 = 0xfbfff0
    public static let moduleColorHex: UInt32 = 0x455c00
    public static let badgeBackgroundHex: UInt32 = 0x0b1412
    public static let quietModules: CGFloat = 4

    private static let ciContext = CIContext(options: nil)
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private static func cgColor(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            colorSpace: sRGB,
            components: [
                CGFloat((hex >> 16) & 255) / 255,
                CGFloat((hex >> 8) & 255) / 255,
                CGFloat(hex & 255) / 255,
                alpha
            ]
        )!
    }

    /// Extracts the trimmed `n × n` ISO QR boolean matrix (excluding CoreImage's built-in quiet-zone border)
    /// and verifies canonical top-left / top-right / bottom-left 7×7 finder orientation.
    public static func qrMatrix(for text: String) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let width = Int(output.extent.width.rounded())
        let height = Int(output.extent.height.rounded())
        guard width > 0, width == height,
              let cgImage = ciContext.createCGImage(output, from: output.extent) else { return nil }

        var pixels = [UInt8](repeating: 255, count: width * height)
        guard let gray = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        gray.interpolationQuality = .none
        gray.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minRow = height
        var maxRow = -1
        var minCol = width
        var maxCol = -1
        for row in 0..<height {
            for col in 0..<width where pixels[row * width + col] < 128 {
                if row < minRow { minRow = row }
                if row > maxRow { maxRow = row }
                if col < minCol { minCol = col }
                if col > maxCol { maxCol = col }
            }
        }
        guard minRow <= maxRow, minCol <= maxCol else { return nil }
        let n = maxRow - minRow + 1
        guard n == maxCol - minCol + 1, n >= 21, (n - 21) % 4 == 0 else { return nil }

        var grid = Array(repeating: Array(repeating: false, count: n), count: n)
        for row in 0..<n {
            for col in 0..<n {
                grid[row][col] = pixels[(minRow + row) * width + (minCol + col)] < 128
            }
        }

        // Self-verify orientation: the 3 finder patterns MUST sit at top-left, top-right, bottom-left (never bottom-right).
        if finderScore(grid, col: n - 7, row: n - 7) > finderScore(grid, col: n - 7, row: 0) {
            grid.reverse()
        }
        guard finderScore(grid, col: 0, row: 0) == 49,
              finderScore(grid, col: n - 7, row: 0) == 49,
              finderScore(grid, col: 0, row: n - 7) == 49 else { return nil }
        return grid
    }

    public static func renderCGImage(for url: URL, pixelSize: Int = 900, brandLogo: CGImage? = nil) -> CGImage? {
        guard pixelSize >= 200,
              let matrix = qrMatrix(for: url.absoluteString) else { return nil }
        let n = matrix.count
        let totalModules = CGFloat(n) + quietModules * 2
        let size = CGFloat(pixelSize)
        let moduleSize = size / totalModules
        let offset = quietModules * moduleSize

        guard let cg = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        cg.setAllowsAntialiasing(true)
        cg.setShouldAntialias(true)
        // Flip Y so (0, 0) is top-left matching row-major `matrix[row][col]`.
        cg.translateBy(x: 0, y: size)
        cg.scaleBy(x: 1, y: -1)

        let cardColor = cgColor(cardBackgroundHex)
        let moduleColor = cgColor(moduleColorHex)
        let badgeColor = cgColor(badgeBackgroundHex)

        cg.setFillColor(cardColor)
        cg.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // Draw the 3 H5-matched super-rounded finder eyes at exact trimmed corners.
        let finderOrigins = [(0, 0), (n - 7, 0), (0, n - 7)]
        for (fc, fr) in finderOrigins {
            drawFinder(
                in: cg,
                origin: CGPoint(x: offset + CGFloat(fc) * moduleSize, y: offset + CGFloat(fr) * moduleSize),
                moduleSize: moduleSize,
                moduleColor: moduleColor,
                cardColor: cardColor
            )
        }

        // Reserve a centered quiet square for the PUBO logo (~22% of code side ≈ 4.8% area, well under Level H 30% limit).
        let centerIndex = Double(n) / 2.0
        let clearHalfModules = Double(n) * 0.115
        let dotRadius = moduleSize * 0.42
        for row in 0..<n {
            for col in 0..<n {
                guard matrix[row][col] else { continue }
                if isInsideFinder(col: col, row: row, size: n) { continue }
                if abs(Double(col) + 0.5 - centerIndex) < clearHalfModules &&
                   abs(Double(row) + 0.5 - centerIndex) < clearHalfModules {
                    continue
                }
                let rect = CGRect(
                    x: offset + CGFloat(col) * moduleSize,
                    y: offset + CGFloat(row) * moduleSize,
                    width: moduleSize,
                    height: moduleSize
                )
                fillRoundedRect(rect, radius: dotRadius, color: moduleColor, in: cg)
            }
        }

        // Center dark PUBO badge matching H5 QR page (`#0B1412` square + white PUBO wordmark).
        let codePixelSpan = CGFloat(n) * moduleSize
        let badgeSide = codePixelSpan * 0.19
        let badgeRect = CGRect(
            x: (size - badgeSide) / 2,
            y: (size - badgeSide) / 2,
            width: badgeSide,
            height: badgeSide
        )
        let haloRect = badgeRect.insetBy(dx: -moduleSize * 0.55, dy: -moduleSize * 0.55)
        fillRoundedRect(haloRect, radius: badgeSide * 0.16, color: cardColor, in: cg)
        fillRoundedRect(badgeRect, radius: badgeSide * 0.10, color: badgeColor, in: cg)

        if let brandLogo {
            let targetWidth = badgeSide * 0.80
            let targetHeight = targetWidth * CGFloat(brandLogo.height) / max(1, CGFloat(brandLogo.width))
            let logoRect = CGRect(
                x: badgeRect.midX - targetWidth / 2,
                y: badgeRect.midY - targetHeight / 2,
                width: targetWidth,
                height: targetHeight
            )
            // Unflip locally so CGContext.draw renders the logo right-side up.
            cg.saveGState()
            cg.translateBy(x: 0, y: logoRect.minY + logoRect.maxY)
            cg.scaleBy(x: 1, y: -1)
            cg.interpolationQuality = .high
            cg.draw(brandLogo, in: logoRect)
            cg.restoreGState()
        }

        return cg.makeImage()
    }

    static func finderScore(_ grid: [[Bool]], col c0: Int, row r0: Int) -> Int {
        var score = 0
        for dr in 0..<7 {
            for dc in 0..<7 {
                let onBorder = dr == 0 || dr == 6 || dc == 0 || dc == 6
                let onCenter = (2...4).contains(dr) && (2...4).contains(dc)
                let expected = onBorder || onCenter
                if grid[r0 + dr][c0 + dc] == expected { score += 1 }
            }
        }
        return score
    }

    private static func isInsideFinder(col: Int, row: Int, size n: Int) -> Bool {
        (col < 7 && row < 7) || (col >= n - 7 && row < 7) || (col < 7 && row >= n - 7)
    }

    private static func drawFinder(
        in cg: CGContext,
        origin: CGPoint,
        moduleSize m: CGFloat,
        moduleColor: CGColor,
        cardColor: CGColor
    ) {
        let outer = CGRect(x: origin.x, y: origin.y, width: 7 * m, height: 7 * m)
        let middle = outer.insetBy(dx: m, dy: m)
        let inner = outer.insetBy(dx: 2 * m, dy: 2 * m)

        fillRoundedRect(outer, radius: 2.1 * m, color: moduleColor, in: cg)
        fillRoundedRect(middle, radius: 1.35 * m, color: cardColor, in: cg)
        fillRoundedRect(inner, radius: 1.2 * m, color: moduleColor, in: cg)
    }

    private static func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: CGColor, in cg: CGContext) {
        let clamped = min(max(0, radius), min(rect.width, rect.height) / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: clamped, cornerHeight: clamped, transform: nil)
        cg.setFillColor(color)
        cg.addPath(path)
        cg.fillPath()
    }
}
#endif
