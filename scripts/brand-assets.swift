// Deterministic build asset from the existing PUBO logo; no new brand artwork.
import AppKit
import Foundation

let source = "App/Assets.xcassets/Brand.imageset/pubo-logo.png"
guard let logo = NSImage(contentsOfFile: source) else { fatalError("Existing PUBO logo missing") }
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Icon context failed") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(calibratedRed: 11/255, green: 20/255, blue: 18/255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let width: CGFloat = 780
let height = width * logo.size.height / logo.size.width
logo.draw(in: NSRect(x: (1024-width)/2, y: (1024-height)/2, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon encoding failed") }
try data.write(to: URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
