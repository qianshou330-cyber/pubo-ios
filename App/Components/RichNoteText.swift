import SwiftUI
import SDWebImage
import PUBOCore

/// TextKit lays out links and emoji attachments in one selectable text flow.
/// Animated attachments are native views positioned over the reserved glyph rects.
struct RichNoteText: UIViewRepresentable {
    let parts: [String]
    let urls: [String: URL]
    let images: [String: UIImage]
    let playing: Bool
    let identifier: String
    let openURL: (URL) -> Void
    var onTap: (() -> Void)?
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> AnimatedTextView {
        let view = AnimatedTextView(usingTextLayoutManager: false)
        view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false
        view.backgroundColor = .clear; view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true; view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = context.coordinator; view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: AnimatedTextView, context: Context) {
        context.coordinator.openURL = openURL; context.coordinator.onTap = onTap; context.coordinator.view = view
        let font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: UIFont.systemFont(ofSize: 14))
        let color = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 222/255, green: 231/255, blue: 228/255, alpha: 1) : UIColor(white: 103/255, alpha: 1) }
        let output = NSMutableAttributedString(string: "")
        for part in parts {
            if let key = urls.keys.first(where: { $0.hasPrefix(part + "https://") }), let image = images[key] {
                let attachment = NSTextAttachment(); attachment.image = image
                let height = font.pointSize * 1.8
                let width = height * min(4, max(0.25, image.size.width / max(1, image.size.height)))
                attachment.bounds = CGRect(x: 0, y: font.descender - 1, width: width, height: height)
                let string = NSMutableAttributedString(attachment: attachment)
                if let animated = image as? SDAnimatedImage, animated.animatedImageFrameCount > 1 { string.addAttribute(.init("PUBOAnimatedImage"), value: animated, range: NSRange(location: 0, length: 1)) }
                output.append(string)
            } else {
                let value = (try? AttributedString(markdown: NativeLink.linkedText(part), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(part)
                for run in value.runs {
                    var traits = UIFontDescriptor.SymbolicTraits()
                    if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true { traits.insert(.traitBold) }
                    if run.inlinePresentationIntent?.contains(.emphasized) == true { traits.insert(.traitItalic) }
                    let runFont = traits.isEmpty ? font : UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor, size: font.pointSize)
                    var attributes: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: color]
                    if let link = run.link { attributes[.link] = link }
                    if run.inlinePresentationIntent?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    output.append(NSAttributedString(string: String(value[run.range].characters), attributes: attributes))
                }
            }
        }
        if !view.attributedText.isEqual(to: output) { view.attributedText = output; view.rebuildAnimations() }
        view.linkTextAttributes = [.foregroundColor: UIColor(red: 0.42, green: 0.63, blue: 0.65, alpha: 1)]
        view.playing = playing; view.accessibilityIdentifier = identifier
        view.accessibilityTraits = onTap == nil ? .staticText : [.staticText, .button]
        view.setNeedsLayout()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AnimatedTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        return CGSize(width: width, height: max(1, uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }
    static func dismantleUIView(_ view: AnimatedTextView, coordinator: Coordinator) { view.clearAnimations(); view.delegate = nil }
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var view: AnimatedTextView?
        var openURL: ((URL) -> Void)?
        var onTap: (() -> Void)?
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool { openURL?(URL); return false }
        private func link(at point: CGPoint, view: UITextView) -> Bool {
            guard view.attributedText.length > 0 else { return false }
            let index = view.layoutManager.characterIndex(for: point, in: view.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            return index < view.attributedText.length && view.attributedText.attribute(.link, at: index, effectiveRange: nil) != nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { guard let view else { return false }; return onTap != nil && !link(at: touch.location(in: view), view: view) }
        @objc func tap(_ recognizer: UITapGestureRecognizer) { if recognizer.state == .ended { onTap?() } }
    }
    final class AnimatedTextView: UITextView {
        var playing = false
        private var overlays: [(NSRange, ProtectedGIFImageView, SDAnimatedImage)] = []
        func clearAnimations() { for (_, view, _) in overlays { view.clear(); view.removeFromSuperview() }; overlays = [] }
        func rebuildAnimations() {
            clearAnimations()
            attributedText.enumerateAttribute(.init("PUBOAnimatedImage"), in: NSRange(location: 0, length: attributedText.length)) { value, range, _ in
                guard let image = value as? SDAnimatedImage else { return }
                let view = ProtectedGIFImageView(frame: .zero); view.isUserInteractionEnabled = false; view.isAccessibilityElement = false; view.maxBufferSize = 1024 * 1024
                addSubview(view); overlays.append((range, view, image))
            }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            for (range, imageView, image) in overlays {
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                imageView.frame = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
                let visible = window != nil && convert(bounds, to: nil).intersects(UIScreen.main.bounds)
                imageView.configure(image, playing: playing && visible, identifier: "timeline.inlineEmoji", open: nil)
            }
        }
        override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { for (_, view, _) in overlays { view.stopAnimating() } } }
    }
}
