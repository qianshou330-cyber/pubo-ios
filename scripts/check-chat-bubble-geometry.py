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


// Independent winding oracle. SwiftUI Path.contains can classify equivalent
// split cubic segments differently near a boundary. No border band is ignored.
struct PrecisePath {
    let path: Path
    let edges: [(CGPoint, CGPoint)]
    init(_ path: Path, tolerance: CGFloat = 0.0001) {
        self.path = path
        var edges: [(CGPoint, CGPoint)] = []
        var current = CGPoint.zero, start = CGPoint.zero
        var openSubpath = false
        func line(_ end: CGPoint) { edges.append((current, end)); current = end }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x+b.x)/2, y: (a.y+b.y)/2)
        }
        func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx=b.x-a.x, dy=b.y-a.y, squared=dx*dx+dy*dy
            if squared == 0 { return hypot(p.x-a.x,p.y-a.y) }
            let t=max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/squared))
            return hypot(p.x-(a.x+t*dx),p.y-(a.y+t*dy))
        }
        func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ depth: Int = 0) {
            if max(distance(b,a,d), distance(c,a,d)) <= tolerance {
                line(d); return
            }
            precondition(depth < 24, "Curve flattening did not converge")
            let ab=mid(a,b), bc=mid(b,c), cd=mid(c,d)
            let abc=mid(ab,bc), bcd=mid(bc,cd), center=mid(abc,bcd)
            cubic(a,ab,abc,center,depth+1); cubic(center,bcd,cd,d,depth+1)
        }
        path.forEach { element in
            switch element {
            case .move(let p):
                if openSubpath { line(start) }
                current=p; start=p; openSubpath=true
            case .line(let p): line(p)
            case .quadCurve(let p, let c):
                let a=current
                cubic(a, CGPoint(x:a.x+2*(c.x-a.x)/3,y:a.y+2*(c.y-a.y)/3),
                      CGPoint(x:p.x+2*(c.x-p.x)/3,y:p.y+2*(c.y-p.y)/3), p)
            case .curve(let p, let c1, let c2): cubic(current,c1,c2,p)
            case .closeSubpath: line(start); openSubpath=false
            }
        }
        if openSubpath { line(start) } // Fill implicitly closes open contours.
        self.edges=edges
    }
    var isEmpty: Bool { path.isEmpty }
    var boundingRect: CGRect { path.boundingRect }
    func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool {
        var winding=0
        for (a,b) in edges {
            if a.y <= p.y && b.y > p.y {
                if (b.x-a.x)*(p.y-a.y)-(p.x-a.x)*(b.y-a.y) > 0 { winding += 1 }
            } else if a.y > p.y && b.y <= p.y {
                if (b.x-a.x)*(p.y-a.y)-(p.x-a.x)*(b.y-a.y) < 0 { winding -= 1 }
            }
        }
        return eoFill ? abs(winding)%2 == 1 : winding != 0
    }
}

var openTriangle=Path()
openTriangle.move(to:CGPoint(x:0,y:0)); openTriangle.addLine(to:CGPoint(x:10,y:0))
openTriangle.addLine(to:CGPoint(x:0,y:10))
check(PrecisePath(openTriangle).contains(CGPoint(x:2,y:2)),"Open contour implicit closure failed")
check(!PrecisePath(openTriangle).contains(CGPoint(x:8,y:8)),"Open contour exterior failed")

var checks = 0
func validate(rect: CGRect, rightPath: Path, leftPath: Path, reportDiagnostics: Bool = false) -> [String] {
    var failures = [String]()
    func check(_ condition: Bool, _ message: String) {
        if !condition && !failures.contains(message) { failures.append(message) }
    }
    let size = (rect.width,rect.height), origin = (rect.minX,rect.minY)
    let right = PrecisePath(rightPath), left = PrecisePath(leftPath)
        if rect.width == 0 || rect.height == 0 {
            check(right.isEmpty && left.isEmpty, "Degenerate rectangle must be empty")
            checks += 1; return failures
        }
        let radius = min(12.0, rect.width / 2, rect.height / 2)
        let inset = radius * 0.13
        for own in [false, true] {
            let actual = own ? right : left
            let finer = PrecisePath(actual.path, tolerance: 0.00001)
            let body = PrecisePath(Path(roundedRect: CGRect(x: rect.minX + (own ? 0 : inset), y: rect.minY + inset,
                width: rect.width - inset, height: rect.height - inset), cornerRadius: radius))
            let finerBody = PrecisePath(body.path, tolerance: 0.00001)
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
            // Device-scale raster containment across every size and orientation.
            // Zero missing pixels required, not a percentage or border exemption.
            for scale in [CGFloat(1), 2, 3] {
                let expected = raster(body.path, rect: rect, scale: scale)
                let observed = raster(actual.path, rect: rect, scale: scale)
                check(!zip(expected,observed).contains { $0.0 > 0 && $0.1 == 0 },
                      "Raster body loss: size=\(size), own=\(own), scale=\(scale)")
            }
            // Sample both former overlap and body interior. Union may add fill but must never remove body fill.
            for ix in 0..<79 { for iy in 0..<79 {
                let p = CGPoint(x: rect.minX + (CGFloat(ix) + 0.371) * rect.width / 79,
                                y: rect.minY + (CGFloat(iy) + 0.629) * rect.height / 79)
                let actualInside=actual.contains(p), bodyInside=body.contains(p)
                check(actualInside == finer.contains(p), "Precision convergence failure")
                check(bodyInside == finerBody.contains(p), "Body precision convergence failure")
                if bodyInside {
                    if reportDiagnostics && !actualInside { diagnose(actual.path, body: body.path, rect: rect, own: own, point: p) }
                    check(actualInside, "Hole in body: \(size), own=\(own), \(p)")
                }
                check(actualInside == actual.contains(p, eoFill: true), "Fill rule disagreement")
                let mirror = CGPoint(x: rect.minX + rect.maxX - p.x, y: p.y)
                check(right.contains(p) == left.contains(mirror), "Left/right asymmetry: size=\(size), origin=\(origin), own=\(own), p=\(p), mirror=\(mirror), right=\(right.contains(p)), left=\(left.contains(mirror)), rightBounds=\(right.boundingRect), leftBounds=\(left.boundingRect)")
                checks += 3
            } }
        }
    return failures
}
// Controls run the same complete validation function as production, not isolated probes.
let controlRect=CGRect(x:0,y:0,width:80,height:32)
let controlRight=PUBOChatBubble(own:true).path(in:controlRect)
let mirrorTransform=CGAffineTransform(a:-1,b:0,c:0,d:1,tx:80,ty:0)
func negative(_ name: String, path: Path, expected: String) {
    let failures=validate(rect:controlRect,rightPath:path,leftPath:path.applying(mirrorTransform))
    check(failures.contains { $0.contains(expected) }, "Negative control ineffective: \(name): \(failures)")
    print("NEGATIVE CONTROL \(name) rejected: \(failures.prefix(3))")
}
let noTail=Path(roundedRect:CGRect(x:0,y:1.56,width:78.44,height:30.44),cornerRadius:12)
negative("missing tail",path:noTail,expected:"Missing curved tail")
let hole=controlRight.subtracting(Path(CGRect(x:30,y:10,width:8,height:8)))
negative("subtracted interior hole",path:hole,expected:"Hole in body")
// Both contour orientations are tested: one cancels nonzero fill, the other
// retains nonzero fill but creates an even-odd hole. Both must be rejected.
var inner=Path()
inner.move(to:CGPoint(x:30,y:10)); inner.addLine(to:CGPoint(x:38,y:10))
inner.addLine(to:CGPoint(x:38,y:18)); inner.addLine(to:CGPoint(x:30,y:18)); inner.closeSubpath()
var compound=controlRight; compound.addPath(inner)
let reversed=inner.applying(CGAffineTransform(a:-1,b:0,c:0,d:1,tx:68,ty:0))
var opposite=controlRight; opposite.addPath(reversed)
let compoundFailures=validate(rect:controlRect,rightPath:compound,leftPath:compound.applying(mirrorTransform))
let oppositeFailures=validate(rect:controlRect,rightPath:opposite,leftPath:opposite.applying(mirrorTransform))
check(compoundFailures.contains { $0.contains("Hole in body") || $0.contains("Fill rule disagreement") },"Compound winding control passed")
check(oppositeFailures.contains { $0.contains("Hole in body") || $0.contains("Fill rule disagreement") },"Reverse winding control passed")
print("NEGATIVE CONTROLS compound and reverse winding rejected")

// Preserve the exact historical point and compare native/independent oracles.
let historicalRect=CGRect(x:0,y:0,width:24,height:24)
let historicalPoint=CGPoint(x:11.353215189873417,y:23.887291139240507)
let historicalPath=PUBOChatBubble(own:false).path(in:historicalRect)
print("C43 POINT native=\(historicalPath.contains(historicalPoint)) precise=\(PrecisePath(historicalPath).contains(historicalPoint)) finer=\(PrecisePath(historicalPath,tolerance:0.00001).contains(historicalPoint))")
checks = 0 // Production count excludes intentional negative cases.
for size in [(0.0,0.0),(0,10),(10,0),(1,1),(2,20),(20,2),(24,24),(80,32),(280,100),(240,240)] {
    for origin in [(0.0,0.0),(23,41)] {
        let rect=CGRect(x:origin.0,y:origin.1,width:size.0,height:size.1)
        let failures=validate(rect:rect,rightPath:PUBOChatBubble(own:true).path(in:rect),
            leftPath:PUBOChatBubble(own:false).path(in:rect),reportDiagnostics:true)
        check(failures.isEmpty,"Production geometry rejected: \(failures.prefix(20))")
    }
}
print("PASS \(checks) production Shape geometry assertions")
'''
with tempfile.TemporaryDirectory() as folder:
    path = Path(folder) / 'BubbleGeometry.swift'
    path.write_text(program)
    binary = Path(folder) / 'BubbleGeometry'
    subprocess.run(['swiftc', '-O', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
