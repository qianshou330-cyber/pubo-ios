// Deterministic build asset from the existing PUBO logo; no new brand artwork.
import AppKit
import Foundation

let source = "App/Assets.xcassets/Brand.imageset/pubo-logo.png"
guard let logo = NSImage(contentsOfFile: source) else { fatalError("Existing PUBO logo missing") }
guard let canvas = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Icon context failed") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
NSColor(calibratedRed: 11/255, green: 20/255, blue: 18/255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let width: CGFloat = 780
let height = width * logo.size.height / logo.size.width
logo.draw(in: NSRect(x: (1024-width)/2, y: (1024-height)/2, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()
guard let rendered = canvas.makeImage() else { fatalError("Icon rendering failed") }
let bitmap = NSBitmapImageRep(cgImage: rendered)
guard !bitmap.hasAlpha, bitmap.pixelsWide == 1024, bitmap.pixelsHigh == 1024, let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon encoding failed") }
try data.write(to: URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))

