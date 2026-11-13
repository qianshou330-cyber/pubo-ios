import XCTest
import UIKit
import Vision

/// One independent observation, with no expected count or fallback value.
struct TabBadgeReading {
    let screenshot: UIImage
    var tabCrop: UIImage?
    var extractedDigits: UIImage?
    var recognizedText: String?
    var failureReason: String?
    var readings: [String] = []

    func attach(to activity: XCTActivity, name: String = "tab-badge") {
        for (suffix, image) in [("screen", Optional(screenshot)), ("tab", tabCrop), ("glyphs", extractedDigits)] {
            guard let image else { continue }
            let attachment = XCTAttachment(image: image)
            attachment.name = name + "-" + suffix; attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        let attachment = XCTAttachment(string: (readings + ["actual=\(recognizedText ?? "nil")", "failure=\(failureReason ?? "none")"]).joined(separator: "\n"))
        attachment.name = name + "-readings"; attachment.lifetime = .keepAlways
        activity.add(attachment)
    }
}

/// Supply the target tab button. Never expands outside its frame or reads AX values.
func readTabBadge(app: XCUIApplication, tab: XCUIElement) -> TabBadgeReading {
    let shot = app.screenshot().image
    var result = TabBadgeReading(screenshot: shot)
    guard tab.exists, tab.elementType == .button else {
        result.failureReason = "Missing button"; return result
    }
    return readTabBadgeImage(shot, buttonFrame: tab.frame, appFrame: app.frame)
}

/// Pure screenshot path, also exercised by synthetic clipping/ambiguity controls.
/// There is no expected digit or accessibility value in this API.
func readTabBadgeImage(_ shot: UIImage, buttonFrame frame: CGRect, appFrame: CGRect) -> TabBadgeReading {
    var result = TabBadgeReading(screenshot: shot)
    guard let screen = shot.cgImage else {
        result.failureReason = "Missing screenshot pixels"; return result
    }
    guard !frame.isEmpty, !frame.isNull, !frame.isInfinite,
          appFrame.width > 0, appFrame.height > 0, appFrame.contains(frame) else {
        result.failureReason = "Invalid button geometry"; return result
    }
    let sx = CGFloat(screen.width) / appFrame.width, sy = CGFloat(screen.height) / appFrame.height
    guard sx.isFinite, sy.isFinite, sx > 0, sy > 0, abs(sx - sy) < 0.05 else {
        result.failureReason = "Inconsistent screenshot scale"; return result
    }
    let x0 = ceil((frame.minX - appFrame.minX) * sx), y0 = ceil((frame.minY - appFrame.minY) * sy)
    let x1 = floor((frame.maxX - appFrame.minX) * sx), y1 = floor((frame.maxY - appFrame.minY) * sy)
    let region = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    guard region.width > 0, region.height > 0,
          let crop = screen.cropping(to: region) else {
        result.failureReason = "Cannot crop button"; return result
    }
    result.tabCrop = UIImage(cgImage: crop)
    result.readings.append("button=\(frame); pixels=\(region); scale=\(sx),\(sy)")
    let w = crop.width, h = crop.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return true
    }
    guard drawn else { result.failureReason = "Cannot rasterize button"; return result }
    var red = (0..<(w * h)).map { i -> Bool in
        let p = i * 4
        return pixels[p] > 155 && pixels[p + 1] < 140 && pixels[p + 2] < 150 && Int(pixels[p]) - Int(pixels[p + 1]) > 75
    }
    var components = [[Int]]()
    for seed in 0..<red.count where red[seed] {
        var queue = [seed], cursor = 0; red[seed] = false
        while cursor < queue.count {
            let i = queue[cursor]; cursor += 1
            let x = i % w, y = i / w
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                let next = ny * w + nx
                if red[next] { red[next] = false; queue.append(next) }
            }
        }
        components.append(queue)
    }
    result.readings.append("redComponents=\(components.count)")
    guard components.count == 1, let component = components.first else {
        result.failureReason = "Red region missing or ambiguous"; return result
    }
    let left = component.map { $0 % w }.min()!, right = component.map { $0 % w }.max()!
    let top = component.map { $0 / w }.min()!, bottom = component.map { $0 / w }.max()!
    let bw = right - left + 1, bh = bottom - top + 1
    let widthPoints = CGFloat(bw) / sx, heightPoints = CGFloat(bh) / sy
    let aspect = CGFloat(bw) / CGFloat(bh)
    let fill = Double(component.count) / Double(bw * bh)
    result.readings.append("badgePixels=\(left),\(top),\(bw),\(bh); points=\(widthPoints)x\(heightPoints); aspect=\(aspect); redFill=\(fill)")
    guard left > 0, top > 0, right < w - 1, bottom < h - 1,
          heightPoints >= 8, heightPoints <= 32, widthPoints >= 8, widthPoints <= 70,
          aspect >= 0.9, aspect <= 4, fill >= 0.35, fill <= 0.95 else {
        result.failureReason = "Clipped or implausible badge geometry"; return result
    }
    // Native badges use Capsule. A cut-off circle padded with white can no
    // longer touch the crop edge, so test its original red outline as well.
    // This is shape validation, not a font template or expected-digit matcher.
    let radius = Double(bh) / 2, tolerance = Double(sx) * 0.5
    let outsideCapsule = component.filter { i in
        let x = Double(i % w - left) + 0.5, y = Double(i / w - top) + 0.5
        let centerX = min(max(x, radius), Double(bw) - radius)
        return hypot(x - centerX, y - radius) > radius + tolerance
    }.count
    result.readings.append("capsuleOutsidePixels=\(outsideCapsule)")
    guard outsideCapsule == 0 else {
        result.failureReason = "Badge red outline is clipped or not a complete capsule"; return result
    }
    var minX = [Int](repeating: w, count: h), maxX = [Int](repeating: -1, count: h)
    for i in component { let y = i / w; minX[y] = min(minX[y], i % w); maxX[y] = max(maxX[y], i % w) }
    // Keep only observed white ink. Normalize its height rather than leaving
    // 2x-device glyphs smaller than 3x-device glyphs for Vision's detector.
    var ink = [(x: Int, y: Int)]()
    for y in top...bottom where minX[y] < maxX[y] {
        for x in minX[y]...maxX[y] {
            let p = (y * w + x) * 4
            if pixels[p] >= 145, pixels[p + 1] >= 145, pixels[p + 2] >= 150 { ink.append((x, y)) }
        }
    }
    guard let inkLeft = ink.map({ $0.x }).min(), let inkRight = ink.map({ $0.x }).max(),
          let inkTop = ink.map({ $0.y }).min(), let inkBottom = ink.map({ $0.y }).max() else {
        result.failureReason = "No white glyphs"; return result
    }
    guard inkLeft > left + 1, inkRight < right - 1,
          inkTop > top + 1, inkBottom < bottom - 1 else {
        result.failureReason = "Glyph touches badge boundary"; return result
    }
    let zoom = max(1, Int(ceil(128.0 / Double(inkBottom - inkTop + 1))))
    let margin = 32
    let outW = (inkRight - inkLeft + 1) * zoom + 2 * margin
    let outH = (inkBottom - inkTop + 1) * zoom + 2 * margin
    var output = [UInt8](repeating: 255, count: outW * outH)
    for pixel in ink {
        for dy in 0..<zoom {
            let start = ((pixel.y - inkTop) * zoom + margin + dy) * outW + (pixel.x - inkLeft) * zoom + margin
            for dx in 0..<zoom { output[start + dx] = 0 }
        }
    }
    result.readings.append("inkBounds=\(inkLeft),\(inkTop),\(inkRight),\(inkBottom); normalizedZoom=\(zoom)")
    guard let provider = CGDataProvider(data: Data(output) as CFData),
          let digits = CGImage(width: outW, height: outH, bitsPerComponent: 8, bitsPerPixel: 8,
                               bytesPerRow: outW, space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
        result.failureReason = "Cannot build observed glyph image"; return result
    }
    result.extractedDigits = UIImage(cgImage: digits)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0
    do {
        try VNImageRequestHandler(cgImage: digits, orientation: .up).perform([request])
        let observations = request.results ?? []
        for (index, observation) in observations.enumerated() {
            result.readings.append("observation[\(index)]=" + observation.topCandidates(3).map { "\($0.string.debugDescription):\($0.confidence)" }.joined(separator: ", "))
        }
        guard observations.count == 1, let candidates = observations.first?.topCandidates(3),
              let best = candidates.first, best.confidence >= 0.5,
              best.string.range(of: "^[0-9]+\\+?$", options: .regularExpression) != nil,
              !candidates.dropFirst().contains(where: { $0.string != best.string && $0.confidence >= 0.5 }) else {
            result.failureReason = "OCR absent, low-confidence, nonnumeric or ambiguous"; return result
        }
        result.recognizedText = best.string
    } catch { result.failureReason = "Vision failed: \(error.localizedDescription)" }
    return result
}
