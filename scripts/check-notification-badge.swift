import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

enum EvidenceError: Error { case missing(String), unreadable, wrongDigits }

/// Optical references from the human-reviewed red “12” in build 136's original
/// simulator recordings. The two numeral shapes are scored separately at either scale.
let references = [
    """
    ...............#####....
    ...####.......########..
    ..#####......##.....###.
    .###.##.....###......##.
    ##...##.....##.......##.
    .....##..............##.
    .....##..............##.
    .....##.............###.
    .....##.............##..
    .....##............##...
    .....##...........##....
    .....##..........##.....
    .....##.........###.....
    .....##........##.......
    .....##.......##........
    .....##......###........
    .....##.....###########.
    .....##.....############
    """,
    """
    .................##.....
    ....###.......#######...
    ..#####......####..####.
    .######......##.....###.
    ###.###.....##.......###
    #...###.....##.......###
    ....###..............###
    ....###..............##.
    ....###.............##..
    ....###...........###...
    ....###...........##....
    ....###..........##.....
    ....###.........###.....
    ....###........###......
    ....###.......###.......
    ....###......###........
    ....###.....############
    ....###.....############
    """
]

func glyphs(_ bitmap: [[Bool]]) -> [[Bool]] {
    let active = (0..<bitmap[0].count).filter { x in bitmap.contains { $0[x] } }
    var ranges: [ClosedRange<Int>] = []
    for column in active {
        if let previous = ranges.last, previous.upperBound + 1 == column {
            ranges[ranges.count - 1] = previous.lowerBound...column
        } else { ranges.append(column...column) }
    }
    return ranges.map { range in
        let occupied = bitmap.indices.filter { y in range.contains { bitmap[y][$0] } }
        guard let first = occupied.first, let last = occupied.last else { return [] }
        return (0..<20).flatMap { y in
            (0..<16).map { x in
                let sy = first + min(last - first, Int((Double(y) + 0.5) * Double(last - first + 1) / 20))
                let sx = range.lowerBound + min(range.count - 1, Int((Double(x) + 0.5) * Double(range.count) / 16))
                return bitmap[sy][sx]
            }
        }
    }
}

func overlap(_ a: [Bool], _ b: [Bool]) -> Double {
    guard a.count == b.count && !a.isEmpty else { return 0 }
    var common = 0, ink = 0
    for i in a.indices where a[i] || b[i] { ink += 1; if a[i] && b[i] { common += 1 } }
    return Double(common) / Double(max(1, ink))
}

func readBitmap(_ url: URL) throws -> [[Bool]] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(source, 0, nil),
          img.width >= 10, img.height >= 10 else { throw EvidenceError.unreadable }
    var data = [UInt8](repeating: 255, count: img.width * img.height)
    try data.withUnsafeMutableBytes { bytes in
        guard let ctx = CGContext(data: bytes.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8,
                                  bytesPerRow: img.width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw EvidenceError.unreadable }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: CGFloat(img.width), height: CGFloat(img.height)))
    }
    return (0..<img.height).map { y in (0..<img.width).map { x in data[y * img.width + x] < 100 } }
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("manifest.json"))) as? [[String: Any]] ?? []
let attachments = manifest.flatMap { $0["attachments"] as? [[String: Any]] ?? [] }
func attachment(_ name: String) throws -> URL {
    guard let item = attachments.first(where: { ($0["suggestedHumanReadableName"] as? String)?.hasPrefix(name + "_0_") == true }),
          let file = item["exportedFileName"] as? String else { throw EvidenceError.missing(name) }
    return dir.appendingPathComponent(file)
}
let mask = try attachment("notification-badge-digits")
let observed = try glyphs(readBitmap(mask))
guard observed.count == 2 else { throw EvidenceError.wrongDigits }
let scores = references.map { sample -> [Double] in
    let expected = glyphs(sample.split(separator: "\n").map { $0.map { $0 == "#" } })
    return (0..<2).map { overlap(expected[$0], observed[$0]) }
}
let best = scores.max { $0.min()! < $1.min()! }!
var files: [String: String] = [:]
for key in ["notification-badge-digits", "notifications-unread-twelve", "notifications-unread-cleared", "notifications-pull-refreshed"] {
    let bytes = try Data(contentsOf: attachment(key))
    files[key] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}
let verified = best.allSatisfy { $0 >= 0.73 }
let result: [String: Any] = ["expected": "12", "observedGlyphCount": observed.count, "digitShapeIoU": best,
                             "minimumEach": 0.73, "passes": verified, "screenshotSHA256": files]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("Visible number 12; digit shape overlap", best, "pass", verified)
if !verified { throw EvidenceError.wrongDigits }
