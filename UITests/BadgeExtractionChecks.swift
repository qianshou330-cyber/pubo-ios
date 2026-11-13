import XCTest
import UIKit

/// Synthetic controls, never presented as application screenshots. These pass
/// complete source images through the same raw-pixel reader as the real UI.
func assertBadgeExtractionControls() {
    let size = CGSize(width: 180, height: 80)
    let badge = CGRect(x: 100, y: 20, width: 18, height: 18)
    for scale in [CGFloat(2), CGFloat(3)] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let full = renderer.image { _ in
            UIColor.white.setFill(); UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            UIColor.red.setFill(); UIBezierPath(roundedRect: badge, cornerRadius: 9).fill()
            let text = "2" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                                                          .foregroundColor: UIColor.white]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2),
                      withAttributes: attributes)
        }
        let frame = CGRect(origin: .zero, size: size)
        XCTAssertNotNil(readTabBadgeImage(full, buttonFrame: frame, appFrame: frame).extractedDigits,
                        "Complete source control must extract at \(scale)x")
        let cuts = [
            "left": CGRect(x: badge.minX, y: badge.minY, width: 6, height: 18),
            "right": CGRect(x: badge.maxX - 6, y: badge.minY, width: 6, height: 18),
            "top": CGRect(x: badge.minX, y: badge.minY, width: 18, height: 6),
            "bottom": CGRect(x: badge.minX, y: badge.maxY - 6, width: 18, height: 6),
            "absent": badge,
        ]
        for (name, cut) in cuts.sorted(by: { $0.key < $1.key }) {
            // Remove part of the ORIGINAL red badge and its ink, then preserve
            // surrounding white space. Padding must not defeat shape checks.
            let clipped = renderer.image { _ in
                full.draw(at: .zero)
                UIColor.white.setFill(); UIBezierPath(rect: cut).fill()
            }
            let reading = readTabBadgeImage(clipped, buttonFrame: frame, appFrame: frame)
            XCTContext.runActivity(named: "Synthetic original-image \(name) \(scale)x control") {
                reading.attach(to: $0, name: "badge-extractor-control-\(name)-\(Int(scale))x")
            }
            XCTAssertNil(reading.extractedDigits, "Invalid original badge must stop before OCR: \(name)")
            XCTAssertNil(reading.recognizedText)
        }
        let duplicate = renderer.image { _ in
            full.draw(at: .zero)
            UIColor.red.setFill()
            UIBezierPath(roundedRect: badge.offsetBy(dx: -50, dy: 0), cornerRadius: 9).fill()
        }
        XCTAssertNil(readTabBadgeImage(duplicate, buttonFrame: frame, appFrame: frame).extractedDigits,
                     "Two independent red regions are ambiguous")
    }
}
