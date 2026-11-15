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


// Independent curve/ray winding, without flattening or a boundary exemption.
// Split cubics at y-derivative roots, then bisect each monotone interval.
struct PrecisePath {
    struct Segment { let a: CGPoint; let b: CGPoint; let c: CGPoint; let d: CGPoint; let line: Bool }
    let path: Path
    let segments: [Segment]
    let iterations: Int
    init(_ path: Path, iterations: Int = 48) {
        self.path=path; self.iterations=iterations
        var segments=[Segment]()
        var current=CGPoint.zero, start=CGPoint.zero, open=false
        func line(_ end: CGPoint) { segments.append(Segment(a:current,b:current,c:end,d:end,line:true)); current=end }
        path.forEach { element in
            switch element {
            case .move(let p):
                if open { line(start) }; current=p; start=p; open=true
            case .line(let p): line(p)
            case .quadCurve(let p, let c):
                let a=current
                segments.append(Segment(a:a,b:CGPoint(x:a.x+2*(c.x-a.x)/3,y:a.y+2*(c.y-a.y)/3),
                    c:CGPoint(x:p.x+2*(c.x-p.x)/3,y:p.y+2*(c.y-p.y)/3),d:p,line:false)); current=p
            case .curve(let p, let c1, let c2):
                segments.append(Segment(a:current,b:c1,c:c2,d:p,line:false)); current=p
            case .closeSubpath: line(start); open=false
            }
        }
        if open { line(start) }
        self.segments=segments
    }
    var isEmpty: Bool { path.isEmpty }
    var boundingRect: CGRect { path.boundingRect }
    func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool {
        let w = winding(at: p)
        return eoFill ? abs(w)%2 == 1 : w != 0
    }
    func winding(at p: CGPoint) -> Int {
        var winding=0
        func value(_ a: CGFloat,_ b: CGFloat,_ c: CGFloat,_ d: CGFloat,_ t: CGFloat) -> CGFloat {
            // de Casteljau avoids cancellation at endpoints.
            let ab=a+(b-a)*t, bc=b+(c-b)*t, cd=c+(d-c)*t
            let abc=ab+(bc-ab)*t, bcd=bc+(cd-bc)*t
            return abc+(bcd-abc)*t
        }
        for s in segments {
            if s.line {
                if (s.a.y <= p.y && p.y < s.d.y) || (s.d.y <= p.y && p.y < s.a.y) {
                    let x=s.a.x+(p.y-s.a.y)*(s.d.x-s.a.x)/(s.d.y-s.a.y)
                    if x > p.x { winding += s.d.y > s.a.y ? 1 : -1 }
                }
                continue
            }
            let a = -s.a.y+3*s.b.y-3*s.c.y+s.d.y
            let b = 2*(s.a.y-2*s.b.y+s.c.y)
            let c = s.b.y-s.a.y
            var cuts: [CGFloat]=[0,1]
            func root(_ t: CGFloat) { if t.isFinite && t > 0 && t < 1 { cuts.append(t) } }
            if a == 0 { if b != 0 { root(-c/b) } }
            else {
                let discriminant=b*b-4*a*c
                if discriminant >= 0 {
                    let radical=sqrt(discriminant)
                    // Stable quadratic formula, including a repeated root.
                    let q = -0.5*(b+(b >= 0 ? radical : -radical))
                    if q == 0 { root(-b/(2*a)) }
                    else { root(q/a); root(c/q) }
                }
            }
            cuts.sort()
            for index in 0..<(cuts.count-1) {
                var lo=cuts[index], hi=cuts[index+1]
                if lo == hi { continue }
                let lowY=value(s.a.y,s.b.y,s.c.y,s.d.y,lo)
                let highY=value(s.a.y,s.b.y,s.c.y,s.d.y,hi)
                let ascending=highY > lowY
                if !((lowY <= p.y && p.y < highY) || (highY <= p.y && p.y < lowY)) { continue }
                for _ in 0..<iterations {
                    let mid=(lo+hi)/2
                    if mid == lo || mid == hi { break }
                    let y=value(s.a.y,s.b.y,s.c.y,s.d.y,mid)
                    if (y < p.y) == ascending { lo=mid } else { hi=mid }
                }
                let t=(lo+hi)/2
                if value(s.a.x,s.b.x,s.c.x,s.d.x,t) > p.x { winding += ascending ? 1 : -1 }
            }
        }
        return winding
    }
}

var openTriangle=Path()
openTriangle.move(to:CGPoint(x:0,y:0)); openTriangle.addLine(to:CGPoint(x:10,y:0))
openTriangle.addLine(to:CGPoint(x:0,y:10))
check(PrecisePath(openTriangle).contains(CGPoint(x:2,y:2)),"Open contour implicit closure failed")
check(!PrecisePath(openTriangle).contains(CGPoint(x:8,y:8)),"Open contour exterior failed")


// Known-answer curve controls exercise extrema/tangencies and quadratic conversion.
func oracleAnswer(_ name: String, _ path: Path, _ point: CGPoint, _ expected: Bool) {
    for iterations in [48,64] {
        let prepared=PrecisePath(path,iterations:iterations)
        check(prepared.contains(point) == expected, "Curve self-test failed: \(name)")
        check(prepared.contains(point,eoFill:true) == expected, "Curve even-odd self-test failed: \(name)")
    }
}
var quadraticArch=Path()
quadraticArch.move(to:CGPoint(x:0,y:0))
quadraticArch.addQuadCurve(to:CGPoint(x:10,y:0),control:CGPoint(x:5,y:10))
quadraticArch.closeSubpath()
oracleAnswer("quadratic interior",quadraticArch,CGPoint(x:5,y:4),true)
oracleAnswer("quadratic above maximum",quadraticArch,CGPoint(x:5,y:6),false)
oracleAnswer("quadratic tangent ray exterior",quadraticArch,CGPoint(x:-1,y:5),false)
var cubicArch=Path()
cubicArch.move(to:CGPoint(x:0,y:0))
cubicArch.addCurve(to:CGPoint(x:12,y:0),control1:CGPoint(x:0,y:12),control2:CGPoint(x:12,y:12))
cubicArch.closeSubpath()
oracleAnswer("cubic interior below extremum",cubicArch,CGPoint(x:6,y:8),true)
oracleAnswer("cubic exterior above extremum",cubicArch,CGPoint(x:6,y:10),false)
oracleAnswer("cubic tangent double contact",cubicArch,CGPoint(x:-1,y:9),false)
var stationaryInflection=Path()
stationaryInflection.move(to:CGPoint(x:0,y:0))
stationaryInflection.addCurve(to:CGPoint(x:10,y:1),control1:CGPoint(x:0,y:1),control2:CGPoint(x:10,y:0))
stationaryInflection.closeSubpath()
// At t=1/4, curve=(1.5625,.4375); closing chord x=4.375.
oracleAnswer("repeated derivative root interior",stationaryInflection,CGPoint(x:2,y:0.4375),true)
oracleAnswer("repeated derivative root exterior",stationaryInflection,CGPoint(x:5,y:0.4375),false)
print("PASS known-answer quadratic, cubic extremum, tangent and stationary-inflection controls")

// Read native path elements directly: conversion to cubic oracle segments can
// itself overflow for finite extreme points and must not contaminate this check.
func nativePointsFinite(_ path: Path) -> Bool {
    var finite = true
    func inspect(_ p: CGPoint) { finite = finite && p.x.isFinite && p.y.isFinite }
    path.forEach { element in
        switch element {
        case .move(let p), .line(let p): inspect(p)
        case .quadCurve(let p, let c): inspect(p); inspect(c)
        case .curve(let p, let a, let b): inspect(p); inspect(a); inspect(b)
        case .closeSubpath: break
        }
    }
    return finite
}
// Invalid/nonrepresentable mirror-offset proposals fail closed.
let huge = CGFloat.greatestFiniteMagnitude
let invalidRects: [CGRect] = [
    CGRect(x:0,y:0,width:CGFloat.infinity,height:32),
    CGRect(x:CGFloat.infinity,y:0,width:20,height:32),
    CGRect(x:0,y:CGFloat.infinity,width:20,height:32),
    CGRect(x:0,y:0,width:20,height:-CGFloat.infinity),
    CGRect(x:CGFloat.nan,y:0,width:20,height:32),
    CGRect(x:0,y:CGFloat.nan,width:20,height:32),
    CGRect(x:0,y:0,width:CGFloat.nan,height:32),
    CGRect(x:0,y:0,width:20,height:CGFloat.nan),
    CGRect(x:0,y:0,width:-20,height:32),
    CGRect(x:0,y:0,width:20,height:-32),
    CGRect(x:huge * 0.75,y:0,width:20,height:32), // finite bounds, overflow mirror offset
    CGRect(x:-huge * 0.75,y:0,width:20,height:32)
]
for rect in invalidRects {
    for own in [false,true] {
        let path = PUBOChatBubble(own:own).path(in:rect)
        check(path.isEmpty,"Invalid geometry must fail closed: \(rect)")
        check(nativePointsFinite(path),"Invalid proposal emitted non-finite points")
    }
}
// Finite extremes may be empty or representable, without prescribing an obsolete
// normalization limitation. Native points must remain finite for both directions.
for rect in [CGRect(x:0,y:0,width:CGFloat.leastNonzeroMagnitude,height:1),
             CGRect(x:0,y:0,width:huge,height:1),
             CGRect(x:0,y:0,width:1,height:huge),
             CGRect(x:-1000000,y:-1000000,width:80,height:32),
             CGRect(x:huge/4,y:huge/4,width:80,height:32),
             CGRect(x:-huge/4,y:-huge/4,width:80,height:32)] {
    for own in [false,true] {
        check(nativePointsFinite(PUBOChatBubble(own:own).path(in:rect)),"Non-finite native geometry: \(rect)")
    }
}
// Split actual production subpaths; verify measured winding, not assumed orientation.
func contours(_ path: Path) -> [Path] {
    var result=[Path](), current=Path()
    path.forEach { e in
        switch e {
        case .move(let p): if !current.isEmpty { result.append(current) }; current=Path(); current.move(to:p)
        case .line(let p): current.addLine(to:p)
        case .quadCurve(let p,let c): current.addQuadCurve(to:p,control:c)
        case .curve(let p,let a,let b): current.addCurve(to:p,control1:a,control2:b)
        case .closeSubpath: current.closeSubpath()
        }
    }
    if !current.isEmpty { result.append(current) }
    return result
}

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
            let finer = PrecisePath(actual.path, iterations: 64)
            let pieces = contours(actual.path).map { PrecisePath($0) }
            var overlapCount = 0
            var fillContractProbes = 0
            let body = PrecisePath(Path(roundedRect: CGRect(x: rect.minX + (own ? 0 : inset), y: rect.minY + inset,
                width: rect.width - inset, height: rect.height - inset), cornerRadius: radius))
            let finerBody = PrecisePath(body.path, iterations: 64)
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
                // Production contract is explicit nonzero. Same-sign overlapping
                // contours must ADD winding; evenodd equivalence is not its contract.
                let ws = pieces.map { $0.winding(at:p) }.filter { $0 != 0 }
                if ws.count >= 2 {
                    overlapCount += 1
                    check(ws.allSatisfy { ($0 > 0) == (ws[0] > 0) }, "Opposite contour winding")
                    check(actualInside, "Nonzero overlap lost")
                    // A body/tail overlap with exactly two unit windings is the
                    // regression probe for accidentally switching to evenodd fill.
                    if ws.count == 2 && ws.allSatisfy({ abs($0) == 1 }) &&
                        (ws[0] > 0) == (ws[1] > 0) {
                        fillContractProbes += 1
                        check(actual.contains(p, eoFill:false), "Explicit nonzero overlap missing")
                        check(!actual.contains(p, eoFill:true), "Expected evenodd overlap counterexample")
                    }
                }
                let mirror = CGPoint(x: rect.minX + rect.maxX - p.x, y: p.y)
                check(right.contains(p) == left.contains(mirror), "Left/right asymmetry: size=\(size), origin=\(origin), own=\(own), p=\(p), mirror=\(mirror), right=\(right.contains(p)), left=\(left.contains(mirror)), rightBounds=\(right.boundingRect), leftBounds=\(left.boundingRect)")
                checks += 3
            } }
            check(overlapCount > 0, "No measured overlap winding samples")
            check(fillContractProbes > 0, "No nonzero/evenodd contract probes")
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
// Same-direction extra contour is valid nonzero fill; opposite-direction
// contour must be rejected by the unchanged body-coverage gate.
var inner=Path()
inner.move(to:CGPoint(x:30,y:10)); inner.addLine(to:CGPoint(x:38,y:10))
inner.addLine(to:CGPoint(x:38,y:18)); inner.addLine(to:CGPoint(x:30,y:18)); inner.closeSubpath()
let probe=CGPoint(x:34,y:14)
let bodySign=PrecisePath(controlRight).winding(at:probe)
if (PrecisePath(inner).winding(at:probe) > 0) != (bodySign > 0) {
    inner=inner.applying(CGAffineTransform(a:-1,b:0,c:0,d:1,tx:68,ty:0))
}
var compound=controlRight; compound.addPath(inner)
let compoundFailures=validate(rect:controlRect,rightPath:compound,leftPath:compound.applying(mirrorTransform))
check(compoundFailures.isEmpty,"Same-winding positive control failed: \(compoundFailures)")
var opposite=controlRight
opposite.addPath(inner.applying(CGAffineTransform(a:-1,b:0,c:0,d:1,tx:68,ty:0)))
negative("reverse winding",path:opposite,expected:"Hole in body")
print("PASS measured same-winding positive control and reversed-winding negative control")

// Preserve the exact historical point and compare native/independent oracles.
let historicalRect=CGRect(x:0,y:0,width:24,height:24)
let historicalPoint=CGPoint(x:11.353215189873417,y:23.887291139240507)
let historicalPath=PUBOChatBubble(own:false).path(in:historicalRect)
print("C43 POINT native=\(historicalPath.contains(historicalPoint)) precise=\(PrecisePath(historicalPath).contains(historicalPoint)) finer=\(PrecisePath(historicalPath,iterations:64).contains(historicalPoint))")
let tinyRect=CGRect(x:0,y:0,width:1,height:1)
let tinyPoint=CGPoint(x:0.8907721518987342,y:0.3370759493670886)
let tinyPath=PUBOChatBubble(own:true).path(in:tinyRect)
print("C45 POINT native=\(tinyPath.contains(tinyPoint)) analytic=\(PrecisePath(tinyPath).contains(tinyPoint)) finer=\(PrecisePath(tinyPath,iterations:64).contains(tinyPoint))")
checks = 0 // Count is informational, not an exact assertion total.
// All original cases remain mandatory. Normal content-domain classification is
// informational only: it never exempts a tiny-case failure from the final gate.
var allFailures = [String]()
var failedCases = 0
for size in [(0.0,0.0),(0,10),(10,0),(1,1),(2,20),(20,2),(24,16),(24,24),(80,32),(280,100),(240,240)] {
    for origin in [(0.0,0.0),(23,41),(-23,-41)] {
        let rect=CGRect(x:origin.0,y:origin.1,width:size.0,height:size.1)
        let domain = size.0 == 0 || size.1 == 0 ? "degenerate" :
            (size.0 >= 24 && size.1 >= 16 ? "normal-content" : "synthetic-tiny")
        let failures=validate(rect:rect,rightPath:PUBOChatBubble(own:true).path(in:rect),
            leftPath:PUBOChatBubble(own:false).path(in:rect),reportDiagnostics:true)
        print("GEOMETRY CASE domain=\(domain) size=\(size) origin=\(origin) failures=\(failures.count)")
        if !failures.isEmpty {
            failedCases += 1
            allFailures.append(contentsOf: failures.map { "domain=\(domain) size=\(size) origin=\(origin): \($0)" })
            print("GEOMETRY CASE FAILURE DETAILS \(failures.prefix(20))")
        }
        fflush(stdout)
    }
}
print("GEOMETRY SUMMARY failedCases=\(failedCases) failures=\(allFailures.count)")
fflush(stdout)
check(allFailures.isEmpty,"Production geometry rejected: \(allFailures.prefix(20))")
print("PASS production Shape geometry cases")

'''
with tempfile.TemporaryDirectory() as folder:
    path = Path(folder) / 'BubbleGeometry.swift'
    path.write_text(program)
    binary = Path(folder) / 'BubbleGeometry'
    subprocess.run(['swiftc', '-O', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
