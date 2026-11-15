#!/usr/bin/env python3
"""Run the actual production Shape on macOS 14+; requires Xcode SwiftUI."""
from pathlib import Path
import subprocess, tempfile
source = Path(__file__).resolve().parents[1] / 'App/Components/PUBOTheme.swift'
shape = source.read_text().split('struct PUBOChatBubble: Shape {', 1)[1]
program = '''import SwiftUI
import Foundation
enum PUBOTheme { static let radius: CGFloat = 12 }
struct PUBOChatBubble: Shape {''' + shape + r'''
func check(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}

// Diagnostics preserve every assertion. These are isolated Shape renders, not app screenshots.
func raster(_ path: Path, rect: CGRect, scale: CGFloat) -> [UInt8] {
    let width = Int(ceil(rect.width * scale)), height = Int(ceil(rect.height * scale))
    var pixels = [UInt8](repeating: 0, count: width * height)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setShouldAntialias(false)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        context.addPath(path.cgPath)
        context.setFillColor(gray: 1, alpha: 1)
        context.fillPath()
    }
    return pixels
}
func diagnose(_ actual: Path, body: Path, rect: CGRect, own: Bool, point: CGPoint) {
    let radius = min(12.0, rect.width / 2, rect.height / 2), inset = radius * 0.13
    let canonicalBody = Path(roundedRect: CGRect(x: rect.minX, y: rect.minY + inset,
        width: rect.width - inset, height: rect.height - inset), cornerRadius: radius)
    let reflectedBody = canonicalBody.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1,
        tx: rect.minX + rect.maxX, ty: 0))
    let sourceBody = own ? canonicalBody : reflectedBody
    let mirror = CGPoint(x: rect.minX + rect.maxX - point.x, y: point.y)
    print("DIAGNOSTIC rect=\(rect) own=\(own) p=\(point) directBody=\(body.contains(point)) reflectedBody=\(sourceBody.contains(point)) inverseCanonical=\(canonicalBody.contains(own ? point : mirror)) actual=\(actual.contains(point))")
    print("DIRECT BODY PATH \(body)")
    print("REFLECTED CANONICAL BODY PATH \(sourceBody)")
    print("ACTUAL OUTLINE PATH \(actual)")
    for scale in [CGFloat(1), 2, 3, 16] {
        let expected = raster(body, rect: rect, scale: scale)
        let canonical = raster(sourceBody, rect: rect, scale: scale)
        let observed = raster(actual, rect: rect, scale: scale)
        let directMissing = zip(expected, observed).filter { $0.0 > 0 && $0.1 == 0 }.count
        let canonicalMissing = zip(canonical, observed).filter { $0.0 > 0 && $0.1 == 0 }.count
        let oracleDisagreement = zip(expected, canonical).filter { $0.0 != $0.1 }.count
        print("RASTER scale=\(scale) directBodyMissingPixels=\(directMissing) canonicalBodyMissingPixels=\(canonicalMissing) oracleDisagreementPixels=\(oracleDisagreement)")
    }
    fflush(stdout)
}

var checks = 0
// Tiny, narrow, short, standard, multiline, attachment; nonzero origin too.
for size in [(0.0, 0.0), (0, 10), (10, 0), (1, 1), (2, 20), (20, 2), (24, 24), (80, 32), (280, 100), (240, 240)] {
    for origin in [(0.0, 0.0), (23, 41)] {
        let rect = CGRect(x: origin.0, y: origin.1, width: size.0, height: size.1)
        let right = PUBOChatBubble(own: true).path(in: rect)
        let left = PUBOChatBubble(own: false).path(in: rect)
        if rect.width == 0 || rect.height == 0 {
            check(right.isEmpty && left.isEmpty, "Degenerate rectangle must be empty")
            checks += 1; continue
        }
        let radius = min(12.0, rect.width / 2, rect.height / 2)
        let inset = radius * 0.13
        for own in [false, true] {
            let actual = own ? right : left
            let body = Path(roundedRect: CGRect(x: rect.minX + (own ? 0 : inset), y: rect.minY + inset,
                width: rect.width - inset, height: rect.height - inset), cornerRadius: radius)
            // A point strictly inside the H5 tail but above the rounded body.
            // A regression returning only the rounded rectangle must fail here.
            let scale = radius * 1.13 / 14.597
            let tailOnly = CGPoint(x: own ? rect.maxX - (14.597 - 14.4) * scale : rect.minX + (14.597 - 14.4) * scale,
                                   y: rect.minY + 1.3 * scale)
            check(!body.contains(tailOnly), "Tail probe must be independent of body")
            check(actual.contains(tailOnly), "Missing curved tail: \(size), own=\(own)")
            // Above the curved tip is empty, not a filled triangular corner.
            let aboveTip = CGPoint(x: tailOnly.x, y: rect.minY + 0.1 * scale)
            check(!actual.contains(aboveTip), "Tail tip lost its curved outline")
            checks += 3
            check(actual.boundingRect.minX >= rect.minX - 0.02 && actual.boundingRect.maxX <= rect.maxX + 0.02,
                  "Horizontal overflow")
            check(actual.boundingRect.minY >= rect.minY - 0.02 && actual.boundingRect.maxY <= rect.maxY + 0.02,
                  "Vertical overflow")
            // Sample both former overlap and body interior. Union may add fill but must never remove body fill.
            for ix in 0..<79 { for iy in 0..<79 {
                let p = CGPoint(x: rect.minX + (CGFloat(ix) + 0.371) * rect.width / 79,
                                y: rect.minY + (CGFloat(iy) + 0.629) * rect.height / 79)
                if body.contains(p) {
                    if !actual.contains(p) { diagnose(actual, body: body, rect: rect, own: own, point: p) }
                    check(actual.contains(p), "Hole in body: \(size), own=\(own), \(p)")
                }
                check(actual.contains(p) == actual.contains(p, eoFill: true), "Fill rule disagreement")
                let mirror = CGPoint(x: rect.minX + rect.maxX - p.x, y: p.y)
                check(right.contains(p) == left.contains(mirror), "Left/right asymmetry: size=\(size), origin=\(origin), own=\(own), p=\(p), mirror=\(mirror), right=\(right.contains(p)), left=\(left.contains(mirror)), rightBounds=\(right.boundingRect), leftBounds=\(left.boundingRect)")
                checks += 3
            } }
        }
    }
}
print("PASS \(checks) production Shape geometry assertions")
'''
with tempfile.TemporaryDirectory() as folder:
    path = Path(folder) / 'BubbleGeometry.swift'
    path.write_text(program)
    subprocess.run(['swift', str(path)], check=True)
